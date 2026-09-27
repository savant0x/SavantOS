package main

import "time"

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
