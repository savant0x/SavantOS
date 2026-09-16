package main

import (
	"strings"
	"testing"
	"time"
)

// withMeteredProbe substitutes a fake platform probe and restores the real
// one; withMeteredAllowed pins the operator override. Both use t.Cleanup.
func withMeteredProbe(t *testing.T, cost meteredCost, source string) {
	t.Helper()
	prev := probeMeteredLinkFn
	probeMeteredLinkFn = func() (meteredCost, string) { return cost, source }
	t.Cleanup(func() { probeMeteredLinkFn = prev })
}

func withMeteredAllowed(t *testing.T, allowed bool) {
	t.Helper()
	prev := allowMeteredOverride.Swap(allowed)
	t.Cleanup(func() { allowMeteredOverride.Store(prev) })
}

// TestMeteredDecisionMatrix is the 3a micro-contract's decision table:
// Windows hint cost × operator override → gate behavior.
func TestMeteredDecisionMatrix(t *testing.T) {
	cases := []struct {
		name      string
		cost      meteredCost
		allowed   bool
		wantBlock bool
		wantSrc   string
	}{
		{"unrestricted-no-override", costUnrestrict, false, false, "windows-hint"},
		{"unknown-no-override", costUnknown, false, false, "windows-hint"},
		{"fixed-no-override-blocks", costFixed, false, true, "windows-hint"},
		{"variable-no-override-blocks", costVariable, false, true, "windows-hint"},
		{"fixed-override-proceeds", costFixed, true, false, "override"},
		{"variable-override-proceeds", costVariable, true, false, "override"},
		{"unrestricted-override-proceeds", costUnrestrict, true, false, "override"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			withMeteredProbe(t, tc.cost, "windows-hint")
			withMeteredAllowed(t, tc.allowed)
			d := evaluateMeteredPolicy()
			if d.metered != tc.cost.metered() || d.allowed != tc.allowed || d.source != tc.wantSrc {
				t.Fatalf("decision = %+v, want metered=%v allowed=%v source=%s", d, tc.cost.metered(), tc.allowed, tc.wantSrc)
			}
			if d.metered && !d.allowed != tc.wantBlock {
				t.Fatalf("block = %v, want %v", d.metered && !d.allowed, tc.wantBlock)
			}
		})
	}
}

// TestMeteredFailOpen pins the fail-open rule: a platform probe error is
// reported honestly but never blocks downloads.
func TestMeteredFailOpen(t *testing.T) {
	withMeteredProbe(t, costUnknown, "windows-hint-error")
	withMeteredAllowed(t, false)
	d := evaluateMeteredPolicy()
	if d.metered || d.allowed {
		t.Fatalf("probe error must not block: %+v", d)
	}
}

// TestMeteredCostClassification pins the cost enum semantics.
func TestMeteredCostClassification(t *testing.T) {
	if !costFixed.metered() || !costVariable.metered() {
		t.Fatal("fixed/variable must count as metered")
	}
	if costUnrestrict.metered() || costUnknown.metered() {
		t.Fatal("unrestricted/unknown must not count as metered")
	}
	names := map[meteredCost]string{costUnknown: "unknown", costUnrestrict: "unrestricted", costFixed: "fixed", costVariable: "variable"}
	for c, want := range names {
		if c.String() != want {
			t.Fatalf("cost %d named %q, want %q", c, c.String(), want)
		}
	}
}

// TestWaitMeteredGatePausesAndClears: the gate must block while the link is
// metered and proceed once it clears — with the poll loop actually sleeping,
// not spinning, and cancellation honored (proven via the cancel path).
func TestWaitMeteredGatePausesAndClears(t *testing.T) {
	configureSetupCancellation(false)
	t.Cleanup(func() { setupCancelPending.Store(false) })

	calls := 0
	withMeteredProbe(t, 0, "") // replaced below; counted via closure
	withMeteredAllowed(t, false)
	probeMeteredLinkFn = func() (meteredCost, string) {
		calls++
		if calls >= 3 {
			return costUnrestrict, "windows-hint"
		}
		return costFixed, "windows-hint"
	}
	// Shrink the poll so the test stays fast while still proving real sleeps.
	prevInterval := meteredPollInterval
	meteredPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { meteredPollInterval = prevInterval })

	start := time.Now()
	if err := waitMeteredGate(); err != nil {
		t.Fatalf("gate returned error: %v", err)
	}
	elapsed := time.Since(start)
	if calls < 3 {
		t.Fatalf("gate returned after %d probes, want >= 3", calls)
	}
	if elapsed < 10*time.Millisecond {
		t.Fatalf("gate returned too fast (%v): the poll loop must sleep between probes", elapsed)
	}
	d := meteredState.Load()
	if d == nil || d.Metered || !d.Allowed && d.Source == "override" {
		t.Fatalf("final recorded decision wrong: %+v", d)
	}
	// The gate-open invariant: unmetered OR allowed.
	if d.Metered && !d.Allowed {
		t.Fatalf("gate recorded a still-blocked state: %+v", d)
	}
}

// TestWaitMeteredGateHonorsCancellation: an operator abort must end the
// wait with errSetupCancelled, not hang forever on a stuck metered link.
func TestWaitMeteredGateHonorsCancellation(t *testing.T) {
	configureSetupCancellation(false)
	withMeteredProbe(t, costVariable, "windows-hint")
	withMeteredAllowed(t, false)
	prevInterval := meteredPollInterval
	meteredPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { meteredPollInterval = prevInterval })

	go func() {
		time.Sleep(20 * time.Millisecond)
		requestSetupCancel()
	}()
	if err := waitMeteredGate(); err != errSetupCancelled {
		t.Fatalf("gate error = %v, want errSetupCancelled", err)
	}
	setupCancelPending.Store(false)
}

// TestDescribeMeteredGate pins the startup provenance strings, including
// the honest non-Windows wording.
func TestDescribeMeteredGate(t *testing.T) {
	if got := describeMeteredGate(false, false, "nonwindows-default"); !strings.Contains(got, "platform hint unavailable") {
		t.Fatalf("nonwindows wording wrong: %q", got)
	}
	if got := describeMeteredGate(true, false, "windows-hint"); !strings.Contains(got, "will pause") {
		t.Fatalf("metered-blocked wording wrong: %q", got)
	}
	if got := describeMeteredGate(true, true, "windows-hint"); !strings.Contains(got, "operator allows") {
		t.Fatalf("override wording wrong: %q", got)
	}
	if got := describeMeteredGate(false, false, "windows-hint"); !strings.Contains(got, "proceed") {
		t.Fatalf("unmetered wording wrong: %q", got)
	}
}
