package main

import (
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// The safety law (FID-2026-0915-004) is testable without any display: the
// verbs' state transitions and refusals ARE the contract on this milestone.

func newTestServer(t *testing.T) *controlServer {
	t.Helper()
	return &controlServer{st: &state{}, done: make(chan struct{})} // conns nil: emit no-ops
}

func TestArmedByDefault(t *testing.T) {
	s := newTestServer(t).lawStatus()
	// FID-2026-0915-005 m2: the daemon holds NO capability until the
	// operator arms it — fail-closed from the first boot.
	if !strings.Contains(s, "armed=false") || !strings.Contains(s, "mechanism=none") {
		t.Fatalf("fresh daemon must be disarmed with no mechanism, got: %s", s)
	}
}

func TestResumeArms(t *testing.T) {
	s := newTestServer(t)
	if got := s.lawResume(); got != "armed" {
		t.Fatalf("RESUME: got %q", got)
	}
	if st := s.lawStatus(); !strings.Contains(st, "armed=true") {
		t.Fatalf("RESUME must arm, got: %s", st)
	}
}

func TestPauseRefusesAfterKill(t *testing.T) {
	s := newTestServer(t)
	s.lawResume()
	if got := s.lawKill(); got != "severed" {
		t.Fatalf("KILL: got %q", got)
	}
	if got := s.lawPause(); !strings.HasPrefix(got, "refused") {
		t.Fatalf("PAUSE after KILL must be refused, got %q", got)
	}
	if got := s.lawResume(); !strings.HasPrefix(got, "refused") {
		t.Fatalf("RESUME after KILL must be refused: no self-recovery verb (FID-2026-0915-004), got %q", got)
	}
	st := s.lawStatus()
	if !strings.Contains(st, "severed=true") || !strings.Contains(st, "armed=false") {
		t.Fatalf("severed state must hold, got: %s", st)
	}
	if !strings.Contains(st, "killAt=") {
		t.Fatalf("kill timestamp must be journaled, got: %s", st)
	}
}

func TestStatusFormatIsStable(t *testing.T) {
	s := newTestServer(t)
	// Exact shape matters: savantctl and the UI parse these keys. Format
	// changes are contract changes and must fail this test loudly.
	want := "armed=false severed=false mechanism=none killAt=never rearm=0"
	if got := s.lawStatus(); got != want {
		t.Fatalf("status format drifted:\n got: %s\nwant: %s", got, want)
	}
}

func TestDispatchIsTotal(t *testing.T) {
	s := newTestServer(t)
	// Every verb answers exactly one line; unknown commands are refused,
	// never ignored (a hung control line is a hang the operator can't see).
	// (QUIT's listener close is guarded for the nil-listener test shape.)
	for _, cmd := range []string{"KILL", "PAUSE", "RESUME", "STATUS", "QUIT", "BOGUS", ""} {
		if got := s.dispatch(cmd); got == "" {
			t.Fatalf("dispatch(%q) returned an empty line", cmd)
		}
	}
}

func TestNotifySocketFormat(t *testing.T) {
	if got := notifyAddr("@/run/user/1000/savant-core/notify"); got != "\x00/run/user/1000/savant-core/notify" {
		t.Fatalf("abstract address must keep the NUL marker, got %q", got)
	}
	if got := notifyAddr("/run/user/1000/savant-core/notify"); got != "/run/user/1000/savant-core/notify" {
		t.Fatalf("concrete path must pass through, got %q", got)
	}
}

func TestControlSocketLifecycle(t *testing.T) {
	rt := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", rt)
	st := &state{}
	srv, err := newControlServer(st)
	if err != nil {
		t.Fatal(err)
	}
	defer srv.l.Close()
	sock := filepath.Join(rt, sockDirName, sockName)
	// The 0600 socket contract is a Linux property (the guest). Windows
	// emulates modes through the read-only bit (reports 0666), so the
	// exact-mode assertion runs only where the property is real.
	if runtime.GOOS == "linux" {
		if err := checkSocketMode(sock); err != nil {
			t.Fatalf("control socket: %v", err)
		}
	}
	// Full round-trip: a client on the private socket can drive the law.
	go srv.run()
	conn, err := dialControl(sock)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if got, err := roundTrip(conn, "STATUS\n"); err != nil || !strings.Contains(got, "armed=false") {
		t.Fatalf("STATUS round-trip: %q, %v", got, err)
	}
	if got, _ := roundTrip(conn, "RESUME\n"); got != "armed" {
		t.Fatalf("RESUME round-trip: %q", got)
	}
	if got, _ := roundTrip(conn, "KILL\n"); got != "severed" {
		t.Fatalf("KILL round-trip: %q", got)
	}
	if got, _ := roundTrip(conn, "RESUME\n"); !strings.HasPrefix(got, "refused") {
		t.Fatalf("post-kill RESUME must be refused over the wire, got %q", got)
	}
	// QUIT over the wire: single reply, then the daemon tears down the
	// listener (idempotent second close must be a no-op, not a panic).
	if got, _ := roundTrip(conn, "QUIT\n"); got != "quit" {
		t.Fatalf("QUIT round-trip: %q", got)
	}
	srv.lawQuit()
}

func TestRefusesNonSocketStaleFile(t *testing.T) {
	rt := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", rt)
	sock := filepath.Join(rt, sockDirName, sockName)
	if err := mkdirAndWrite(sock, "not a socket"); err != nil {
		t.Fatal(err)
	}
	if _, err := newControlServer(&state{}); err == nil {
		t.Fatal("must refuse to clobber a non-socket file at the control path")
	}
}
