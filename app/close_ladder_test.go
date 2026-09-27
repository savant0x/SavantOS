package main

import (
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
