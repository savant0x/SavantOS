// Savant Core — the Phase 3 agent control-plane daemon (FID-2026-0915-005).
//
// Milestone 2 shape: the control plane only. The daemon serves one private
// peer-to-peer control socket (no system bus, no session bus) with the
// kill/pause/resume/status verbs of the safety-law contract, logs
// structured lines to the journal, and notifies readiness to systemd
// (Type=notify). It holds no input capability and no vision plane yet —
// those land in milestones 3–4 (see -> act -> sever-by-default,
// FID-2026-0915-005). A kill on this milestone is therefore a no-op state
// transition, and Status reports it honestly: armed=false, mechanism=none.
package main

import (
	"fmt"
	"os"
)

// state lives in control.go beside the verbs that mutate it.

// logLine writes one structured line to stdout, which journald captures into
// the user unit's journal. Key=value keeps `journalctl -o cat` grep-able and
// the future json conversion trivial.
func logLine(event string, kv ...string) {
	line := "savant-core: event=" + event
	for i := 0; i+1 < len(kv); i += 2 {
		line += " " + kv[i] + "=" + kv[i+1]
	}
	fmt.Println(line)
}

// notifyReady implements the sd_notify(3) READY=1 contract over the
// $NOTIFY_SOCKET abstract-socket address, so the unit can be Type=notify.
// The socket path is checked at runtime: under `systemd-run --user` tests or
// a plain shell, the variable is unset and readiness reporting is skipped
// (the daemon still runs — same fail-open-on-observability stance as the
// launcher's probe absence handling).
func notifyReady() bool {
	sock := os.Getenv("NOTIFY_SOCKET")
	if sock == "" {
		return false
	}
	// Abstract namespace sockets (@...) are Linux-specific; unix socket
	// paths are the concrete alternative. Only @ is used by systemd user
	// units, but handle both without trusting the address shape.
	// (The datagram write is best-effort: a failed notify must not take
	// the daemon down — systemd's start-up timeout is the backstop.)
	return notifySocket(sock) == nil
}

func main() {
	logLine("start", "pid", fmt.Sprint(os.Getpid()),
		"cap", "none", // milestone marker: no capability planes bound yet
		"law", "FID-2026-0915-004")

	st := &state{armed: false}

	srv, err := newControlServer(st)
	if err != nil {
		logLine("fatal", "err", err.Error())
		os.Exit(1)
	}

	if notifyReady() {
		logLine("ready", "notified", "sd_notify")
		// Service the WatchdogSec contract for the unit (no-op outside
		// systemd): a hung core must be killed, never left acting.
		watchdogLoop()
	} else {
		// No NOTIFY_SOCKET (interactive/dev run): log readiness anyway so
		// the demo transcript always has the line.
		logLine("ready", "notified", "none")
	}

	// The daemon's whole job on this milestone is to exist and answer.
	// Run until the control plane's Quit verb or the socket dies.
	if err := srv.run(); err != nil {
		logLine("fatal", "err", err.Error())
		os.Exit(1)
	}
	logLine("stop")
}
