package main

import (
	"sync/atomic"
	"time"
)

// The close contract must not depend on PowerDevil: its power-button handler
// silently dropped a confirmed close once (FID-2026-0915-002), leaving a
// healthy guest running while the launcher waited forever. This ladder is the
// launcher-authoritative fallback chain from that FID's design of record:
// graceful ACPI powerdown first, a bounded verify, then the guest-side
// privileged shutdown (systemctl poweroff -i over the ssh plane), and finally
// the forced stop the confirmed close already authorized (the waitExit-class
// QEMU kill). Every step is logged so a dropped power event can never again
// look like a clean close.

type closeLadderOps struct {
	// powerdown sends QMP system_powerdown (the graceful first attempt).
	powerdown func() error
	// stillRunning reports whether the guest has NOT started going down.
	stillRunning func() bool
	// escalate requests the guest-side shutdown through the privileged
	// plane. nil when the session has none (no forward to the guest sshd).
	escalate func() error
	// forceStop kills the QEMU process; the supervisor reaps it as usual.
	forceStop func()
	logf      func(format string, a ...any)
}

type closeLadderTimings struct {
	// verifyWindow bounds the graceful attempt before escalating.
	verifyWindow time.Duration
	// escalateWindow bounds the escalated attempt before forcing a stop.
	escalateWindow time.Duration
	poll           time.Duration
}

var defaultCloseLadderTimings = closeLadderTimings{
	verifyWindow:   10 * time.Second,
	escalateWindow: 20 * time.Second,
	poll:           2 * time.Second,
}

// runCloseLadder executes one bounded close and returns once the guest is
// going down or has been stopped. The graceful path stays first (unsaved work
// is only ever at risk after the escalation chain is exhausted).
func runCloseLadder(ops closeLadderOps, t closeLadderTimings) {
	if err := ops.powerdown(); err != nil {
		ops.logf("close ladder: powerdown failed: %v", err)
	} else {
		ops.logf("close ladder: power button sent (graceful attempt)")
	}
	if waitForGuestDown(ops, t.verifyWindow, t.poll) {
		ops.logf("close ladder: guest is shutting down (no escalation needed)")
		return
	}
	ops.logf("close ladder: guest still running after %s (power-event drop family, FID-2026-0915-002) - escalating", t.verifyWindow)
	if ops.escalate == nil {
		ops.logf("close ladder: no privileged escalation plane in this session (ssh not requested)")
	} else if err := ops.escalate(); err != nil {
		ops.logf("close ladder: privileged shutdown failed: %v", err)
	} else {
		ops.logf("close ladder: privileged shutdown requested (systemctl poweroff -i)")
	}
	if err := ops.powerdown(); err != nil {
		ops.logf("close ladder: second powerdown failed: %v", err)
	}
	if waitForGuestDown(ops, t.escalateWindow, t.poll) {
		ops.logf("close ladder: guest is shutting down after escalation")
		return
	}
	ops.logf("close ladder: shutdown not honored after escalation - forcing QEMU to stop (confirmed close contract)")
	ops.forceStop()
}

// A confirmed close runs the ladder on its own goroutine, so the guard's
// confirmation loop stays free for a second close request. The exit path then
// has to wait for that verdict: supervise returns the moment the guest powers
// off, main logs the exit and returns, and the ladder goroutine is killed
// mid-poll - which is why the rung line ("guest is shutting down", "forcing
// QEMU to stop") never reached the log in a real session. Without it a
// dropped power event still looks like a clean close, which is exactly what
// this ladder exists to make impossible.
var (
	closeLadderInFlight atomic.Bool
	closeLadderVerdict  = make(chan struct{}, 1)
)

// ladderWorstCase is the ladder's own bound - the graceful verify window plus
// the escalated one - with a margin for the poll in flight. Derived from the
// same timings the ladder runs on, so the exit wait can never be shorter than
// the work it is waiting for.
func ladderWorstCase() time.Duration {
	t := defaultCloseLadderTimings
	return t.verifyWindow + t.escalateWindow + 10*time.Second
}

// startCloseLadder runs the ladder on its own goroutine and marks it in
// flight so the exit path can wait for the verdict.
func startCloseLadder(ops closeLadderOps, t closeLadderTimings) {
	closeLadderInFlight.Store(true)
	go func() {
		runCloseLadder(ops, t)
		// Verdict first, then clear: a waiter that observes in-flight as
		// false is guaranteed the rung line is already in the log.
		closeLadderVerdict <- struct{}{}
		closeLadderInFlight.Store(false)
	}()
}

// awaitCloseLadderVerdict blocks until an in-flight ladder has logged its
// rung, or the window elapses. It never hangs the exit: a ladder that cannot
// finish is logged and the process leaves anyway, because an exit with a
// missing line is strictly better than an exit that never happens.
func awaitCloseLadderVerdict(window time.Duration, logLine func(string, ...any)) {
	if !closeLadderInFlight.Load() {
		return // no confirmed close is running; nothing to wait for
	}
	select {
	case <-closeLadderVerdict:
	case <-time.After(window):
		logLine("close ladder: no verdict within %s before exit (the ladder was still running)", window)
	}
}

// waitForGuestDown polls until the guest has started going down. The window
// is bounded: a guest still up past it is exactly the incident case.
func waitForGuestDown(ops closeLadderOps, window, poll time.Duration) bool {
	if poll <= 0 {
		poll = window
	}
	deadline := time.Now().Add(window)
	for {
		if !ops.stillRunning() {
			return true
		}
		if !time.Now().Before(deadline) {
			return false
		}
		time.Sleep(poll)
	}
}
