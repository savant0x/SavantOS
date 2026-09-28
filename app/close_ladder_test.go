package main

import (
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"
)

type ladderRecorder struct {
	mu     sync.Mutex
	events []string
}

func (r *ladderRecorder) add(event string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.events = append(r.events, event)
}

func (r *ladderRecorder) snapshot() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.events...)
}

func fastLadderTimings() closeLadderTimings {
	return closeLadderTimings{verifyWindow: 30 * time.Millisecond, escalateWindow: 30 * time.Millisecond, poll: 5 * time.Millisecond}
}

// resetCloseLadderState clears the package-level coordination between tests.
func resetCloseLadderState() {
	closeLadderInFlight.Store(false)
	select {
	case <-closeLadderVerdict:
	default:
	}
}

// No confirmed close means no wait at all: the normal shutdown path must not
// pay for a verdict that was never requested.
func TestAwaitCloseLadderVerdictReturnsImmediatelyWhenIdle(t *testing.T) {
	resetCloseLadderState()
	rec := &ladderRecorder{}
	start := time.Now()
	awaitCloseLadderVerdict(5*time.Second, func(line string, _ ...any) { rec.add(line) })
	if elapsed := time.Since(start); elapsed > 250*time.Millisecond {
		t.Fatalf("waited %s with no close in flight, want an immediate return", elapsed)
	}
	if got := rec.snapshot(); len(got) != 0 {
		t.Fatalf("logged %v with no close in flight, want nothing logged", got)
	}
}

// The regression this fixes: a ladder that is still running when the guest
// powers off must be waited for, so its rung line lands in the log before the
// process exits.
func TestAwaitCloseLadderVerdictWaitsForTheRung(t *testing.T) {
	resetCloseLadderState()
	defer resetCloseLadderState()
	rec := &ladderRecorder{}

	down := make(chan struct{})
	go func() {
		time.Sleep(80 * time.Millisecond)
		close(down)
	}()
	startCloseLadder(closeLadderOps{
		powerdown: func() error { return nil },
		stillRunning: func() bool {
			select {
			case <-down:
				return false
			default:
				return true
			}
		},
		escalate:  func() error { return nil },
		forceStop: func() {},
		logf:      func(format string, a ...any) { rec.add(fmt.Sprintf(format, a...)) },
	}, closeLadderTimings{verifyWindow: 3 * time.Second, escalateWindow: time.Second, poll: 10 * time.Millisecond})

	start := time.Now()
	awaitCloseLadderVerdict(5*time.Second, func(line string, _ ...any) { rec.add("exit:" + line) })
	elapsed := time.Since(start)

	if elapsed < 70*time.Millisecond {
		t.Fatalf("await returned after %s, but the ladder was still polling; it must wait for the rung", elapsed)
	}
	var rung bool
	for _, e := range rec.snapshot() {
		if strings.Contains(e, "shutting down") {
			rung = true
		}
	}
	if !rung {
		t.Fatalf("no rung line was logged before the exit; events = %v", rec.snapshot())
	}
	if closeLadderInFlight.Load() {
		t.Fatal("ladder still marked in flight after its verdict was consumed")
	}
}

// A ladder that never finishes must not park the exit: the wait is bounded
// and says so in the log.
func TestAwaitCloseLadderVerdictIsBounded(t *testing.T) {
	resetCloseLadderState()
	defer resetCloseLadderState()
	rec := &ladderRecorder{}

	block := make(chan struct{})
	defer func() {
		close(block)
		// let the released goroutine finish before the next test resets state
		time.Sleep(50 * time.Millisecond)
	}()
	startCloseLadder(closeLadderOps{
		powerdown:    func() error { return nil },
		stillRunning: func() bool { return true },
		escalate:     func() error { return nil },
		forceStop:    func() { <-block }, // wedged: never returns
		logf:         func(string, ...any) {},
	}, fastLadderTimings())

	start := time.Now()
	awaitCloseLadderVerdict(80*time.Millisecond, func(line string, _ ...any) { rec.add(line) })
	elapsed := time.Since(start)

	if elapsed > time.Second {
		t.Fatalf("bounded wait took %s, want it capped by the window", elapsed)
	}
	var warned bool
	for _, e := range rec.snapshot() {
		if strings.Contains(e, "no verdict within") {
			warned = true
		}
	}
	if !warned {
		t.Fatalf("a timed-out wait must say so in the log; events = %v", rec.snapshot())
	}
}

// The exit wait must never be shorter than the ladder it waits for, or it
// would reintroduce the race it exists to close.
func TestLadderWorstCaseExceedsTheLadderItWaitsFor(t *testing.T) {
	timings := defaultCloseLadderTimings
	if got, floor := ladderWorstCase(), timings.verifyWindow+timings.escalateWindow; got <= floor {
		t.Fatalf("ladderWorstCase() = %s, want more than the ladder's own %s", got, floor)
	}
}

// The graceful path: the guest acts on the power button inside the verify
// window, so the ladder must not escalate or force anything.
func TestCloseLadderGracefulPath(t *testing.T) {
	rec := &ladderRecorder{}
	runCloseLadder(closeLadderOps{
		powerdown:    func() error { rec.add("powerdown"); return nil },
		stillRunning: func() bool { return false },
		escalate:     func() error { rec.add("escalate"); return nil },
		forceStop:    func() { rec.add("force-stop") },
		logf:         func(string, ...any) {},
	}, fastLadderTimings())
	got := rec.snapshot()
	if len(got) != 1 || got[0] != "powerdown" {
		t.Fatalf("ladder events = %v, want [powerdown]", got)
	}
}

// The incident shape: the guest drops the power event, the privileged
// escalation lands, and the guest goes down. No forced stop.
func TestCloseLadderEscalatesAndStops(t *testing.T) {
	rec := &ladderRecorder{}
	var escalated sync.Map
	runCloseLadder(closeLadderOps{
		powerdown: func() error { rec.add("powerdown"); return nil },
		stillRunning: func() bool {
			_, done := escalated.Load("done")
			return !done // down only after the escalation landed
		},
		escalate: func() error {
			rec.add("escalate")
			escalated.Store("done", true)
			return nil
		},
		forceStop: func() { rec.add("force-stop") },
		logf:      func(string, ...any) {},
	}, fastLadderTimings())
	got := rec.snapshot()
	want := []string{"powerdown", "escalate", "powerdown"}
	if len(got) != len(want) {
		t.Fatalf("ladder events = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("ladder events = %v, want %v", got, want)
		}
	}
}

// Nothing works: the close must still be bounded and end in the confirmed
// close's forced stop.
func TestCloseLadderForcesStopWhenNothingHonorsShutdown(t *testing.T) {
	rec := &ladderRecorder{}
	runCloseLadder(closeLadderOps{
		powerdown:    func() error { rec.add("powerdown"); return nil },
		stillRunning: func() bool { return true },
		escalate:     func() error { rec.add("escalate"); return nil },
		forceStop:    func() { rec.add("force-stop") },
		logf:         func(string, ...any) {},
	}, fastLadderTimings())
	got := rec.snapshot()
	want := []string{"powerdown", "escalate", "powerdown", "force-stop"}
	if len(got) != len(want) {
		t.Fatalf("ladder events = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("ladder events = %v, want %v", got, want)
		}
	}
}

// A session without an ssh plane has no escalation; the close must still be
// bounded (and must not pretend an escalation happened).
func TestCloseLadderWithoutEscalationPlane(t *testing.T) {
	rec := &ladderRecorder{}
	runCloseLadder(closeLadderOps{
		powerdown:    func() error { rec.add("powerdown"); return nil },
		stillRunning: func() bool { return true },
		escalate:     nil,
		forceStop:    func() { rec.add("force-stop") },
		logf:         func(string, ...any) {},
	}, fastLadderTimings())
	got := rec.snapshot()
	want := []string{"powerdown", "powerdown", "force-stop"}
	if len(got) != len(want) {
		t.Fatalf("ladder events = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("ladder events = %v, want %v", got, want)
		}
	}
}
