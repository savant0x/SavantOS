package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	sockDirName = "savant-core"
	sockName    = "control.sock"
)

// errSevered is the law refusing re-activation: once the kill switch fires,
// the operator action that restores any capability is a session restart
// (FID-2026-0915-004). The daemon offers no self-recovery verb by design.
var errSevered = errors.New("refused: kill switch engaged this session; re-arm requires session restart")

// controlServer owns the PRIVATE control endpoint — one Unix socket in the
// user's runtime dir, never the session or system bus (FID-2026-0915-004:
// operator verbs must survive session-bus health, and other sessions must
// not reach the core). Socket permissions are the gate: 0600 inside a 0700
// dir.
//
// Wire protocol (v1, grep-able, peer-to-peer): one command word per line,
// one response line back.
//
//	KILL\n    -> "severed\n"
//	PAUSE\n   -> "paused\n" | "refused ..."
//	RESUME\n  -> "armed\n"  | "refused ..."
//	STATUS\n  -> "armed=... severed=... mechanism=none killAt=... rearm=N\n"
//	QUIT\n    -> "quit\n"
//
// DBus surface (dev.savant.Core1) is the m4 UI milestone's shape; this
// socket carries the identical verb set until then, so the safety law is
// enforceable from day one with zero dependencies.
type controlServer struct {
	st *state
	l  net.Listener

	connsMu sync.Mutex
	conns   map[net.Conn]struct{}

	once sync.Once // Quit is idempotent; listener closes exactly once
	done chan struct{}
}

// state is the control-plane state of record (moved here from main.go so
// the verbs and their state live in one file).
type state struct {
	mu       sync.Mutex
	armed    bool      // operator granted action capability (UI ack)
	severed  bool      // kill switch fired this session
	killAt   time.Time // last kill timestamp (operator journal)
	rearmCnt int       // re-arm counter since last kill
}

func newControlServer(st *state) (*controlServer, error) {
	rt := os.Getenv("XDG_RUNTIME_DIR")
	if rt == "" {
		return nil, errors.New("XDG_RUNTIME_DIR is not set; refusing a pathless control socket")
	}
	dir := filepath.Join(rt, sockDirName)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("control dir: %w", err)
	}
	sock := filepath.Join(dir, sockName)
	// A previous instance that died uncleanly leaves the socket node behind
	// (bind refuses it). Remove only if it IS a socket — never clobber a
	// stranger's file.
	if fi, err := os.Lstat(sock); err == nil {
		if fi.Mode()&os.ModeSocket == 0 {
			return nil, fmt.Errorf("refusing to remove non-socket %s", sock)
		}
		if err := os.Remove(sock); err != nil {
			return nil, fmt.Errorf("stale control socket: %w", err)
		}
	}
	l, err := net.Listen("unix", sock)
	if err != nil {
		return nil, fmt.Errorf("control socket: %w", err)
	}
	if err := os.Chmod(sock, 0o600); err != nil {
		_ = l.Close()
		return nil, fmt.Errorf("control socket mode: %w", err)
	}
	return &controlServer{
		st:    st,
		l:     l,
		conns: make(map[net.Conn]struct{}),
		done:  make(chan struct{}),
	}, nil
}

// run accepts operator connections until Quit.
func (s *controlServer) run() error {
	for {
		conn, err := s.l.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return nil
			}
			return err
		}
		go s.serveConn(conn)
	}
}

func (s *controlServer) serveConn(conn net.Conn) {
	s.connsMu.Lock()
	s.conns[conn] = struct{}{}
	s.connsMu.Unlock()
	defer func() {
		s.connsMu.Lock()
		delete(s.conns, conn)
		s.connsMu.Unlock()
		_ = conn.Close()
	}()

	r := bufio.NewReader(conn)
	for {
		// ReadLock without deadline would wedge a dead peer forever; the
		// watchdog restarts the daemon anyway, but a per-line deadline
		// keeps one hung operator client from pinning a goroutine.
		_ = conn.SetReadDeadline(time.Now().Add(5 * time.Minute))
		line, err := r.ReadString('\n')
		if err != nil {
			return
		}
		cmd := strings.ToUpper(strings.TrimSpace(line))
		if cmd == "" {
			continue
		}
		resp := s.dispatch(cmd)
		_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
		if _, werr := io.WriteString(conn, resp+"\n"); werr != nil {
			return
		}
		if cmd == "QUIT" {
			return
		}
	}
}

// dispatch is the entire verb table. Keep it exhaustive and total: every
// command word returns exactly one response line.
func (s *controlServer) dispatch(cmd string) string {
	switch cmd {
	case "KILL":
		return s.lawKill()
	case "PAUSE":
		return s.lawPause()
	case "RESUME":
		return s.lawResume()
	case "STATUS":
		return s.lawStatus()
	case "QUIT":
		return s.lawQuit()
	default:
		return "refused unknown-command"
	}
}

func (s *controlServer) lawKill() string {
	s.st.mu.Lock()
	s.st.armed = false
	s.st.severed = true
	s.st.killAt = time.Now()
	s.st.mu.Unlock()
	// Milestone-2 honesty: no capability plane is bound yet, so this is a
	// state transition, not a severance — the log says so, and Status
	// reports mechanism=none. The contract hardens in m4 (EIS bind) where
	// the same verb becomes fd revocation (FID-2026-0915-003).
	logLine("law_kill", "mechanism", "none",
		"note", "no capability planes bound (FID-2026-0915-005 m2)")
	return "severed"
}

func (s *controlServer) lawPause() string {
	s.st.mu.Lock()
	defer s.st.mu.Unlock()
	if s.st.severed {
		logLine("law_refused", "verb", "PAUSE", "why", "severed")
		return "refused " + errSevered.Error()
	}
	s.st.armed = false
	logLine("law_pause")
	return "paused"
}

func (s *controlServer) lawResume() string {
	s.st.mu.Lock()
	defer s.st.mu.Unlock()
	if s.st.severed {
		logLine("law_refused", "verb", "RESUME", "why", "severed")
		return "refused " + errSevered.Error()
	}
	s.st.armed = true
	s.st.rearmCnt++
	logLine("law_resume", "rearm", fmt.Sprint(s.st.rearmCnt))
	return "armed"
}

// lawStatus is the machine-readable state line: grep-able, no variants.
// mechanism=none until the input plane lands (m4).
func (s *controlServer) lawStatus() string {
	s.st.mu.Lock()
	defer s.st.mu.Unlock()
	killed := "never"
	if !s.st.killAt.IsZero() {
		killed = s.st.killAt.UTC().Format(time.RFC3339)
	}
	return fmt.Sprintf("armed=%t severed=%t mechanism=none killAt=%s rearm=%d",
		s.st.armed, s.st.severed, killed, s.st.rearmCnt)
}

func (s *controlServer) lawQuit() string {
	s.once.Do(func() {
		close(s.done)
		// l is nil only when dispatch is driven without a bound listener
		// (tests); Close on a live listener is the production path.
		if s.l != nil {
			_ = s.l.Close()
		}
	})
	logLine("law_quit")
	return "quit"
}

// emit fans one event line to every connected operator client. (The DBus
// LawEvent signal of the design becomes this stream until m4.)
func (s *controlServer) emit(name, detail string) {
	s.connsMu.Lock()
	conns := make([]net.Conn, 0, len(s.conns))
	for c := range s.conns {
		conns = append(conns, c)
	}
	s.connsMu.Unlock()
	for _, c := range conns {
		_ = c.SetWriteDeadline(time.Now().Add(time.Second))
		_, _ = io.WriteString(c, fmt.Sprintf("event %s %s\n", name, detail))
	}
}
