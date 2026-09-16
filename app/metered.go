package main

// Metered-link policy for payload downloads (FID-2026-0914-002 step 3a).
//
// Windows exposes the OS's per-connection cost hint through
// GetNetworkConnectivityHint (Iphlpapi.dll — verified live on 2026-09-16:
// export present, struct is three 32-bit fields at offsets 0/4/8). When the
// OS says the link is metered (cost Fixed or Variable), full payload
// downloads pause until the link is unrestricted or the operator allows
// them. Small authenticated metadata (SHA256SUMS, update manifests) stays
// exempt: kilobytes, not gigabytes. The escape hatch is the settings row
// below and the -allow-metered flag, per the 3a micro-contract.

import (
	"fmt"
	"sync/atomic"
	"time"
)

// allowMeteredOverride mirrors the -allow-metered flag into the gate. Set
// once at startup after settings/flag precedence resolves; read by the
// download gate on any goroutine.
var allowMeteredOverride atomic.Bool

// meteredState records why the gate last decided, for diagnostics.
var meteredState atomic.Pointer[meteredDecision]

type meteredDecision struct {
	Metered   bool
	Allowed   bool
	Cost      string
	Source    string // "windows-hint", "nonwindows-default", "override"
	CheckedAt time.Time
}

// meteredCost is NL_NETWORK_CONNECTIVITY_HINT's Cost field
// (winnetwk.h NL_NETWORK_COST): Unrestricted / Fixed / Variable.
type meteredCost int

const (
	costUnknown    meteredCost = 0
	costUnrestrict meteredCost = 1
	costFixed      meteredCost = 2
	costVariable   meteredCost = 3
)

func (c meteredCost) metered() bool {
	return c == costFixed || c == costVariable
}

func (c meteredCost) String() string {
	switch c {
	case costUnrestrict:
		return "unrestricted"
	case costFixed:
		return "fixed"
	case costVariable:
		return "variable"
	default:
		return "unknown"
	}
}

// meteredPolicyDecision is the gate's input contract: the current link's
// cost state, whether it counts as metered, and whether downloading on it
// is allowed by settings/flags.
type meteredPolicyDecision struct {
	metered bool
	allowed bool
	cost    meteredCost
	source  string
}

// evaluateMeteredPolicy combines the platform hint with the operator's
// preference. Platform probe failures are fail-open (report not metered)
// on purpose: a broken hint must never block a normal machine's downloads.
// probeMeteredLinkFn indirection lets tests substitute the platform probe;
// production always uses the real one.
var probeMeteredLinkFn = probeMeteredLink

func evaluateMeteredPolicy() meteredPolicyDecision {
	cost, source := probeMeteredLinkFn()
	return combineMeteredPolicy(cost, source)
}

// combineMeteredPolicy is the pure decision core: hint cost + operator
// override → gate decision. Separated from the probe so the full matrix
// is testable on any OS.
func combineMeteredPolicy(cost meteredCost, source string) meteredPolicyDecision {
	allowed := allowMeteredOverride.Load()
	if allowed {
		// The override wins regardless of the hint's answer; the cost still
		// informs the log line so the operator sees the link's real state.
		return meteredPolicyDecision{metered: cost.metered(), allowed: true, cost: cost, source: "override"}
	}
	return meteredPolicyDecision{metered: cost.metered(), allowed: false, cost: cost, source: source}
}

// recordMeteredDecision stores the last gate evaluation for diagnostics.
func recordMeteredDecision(d meteredPolicyDecision) {
	meteredState.Store(&meteredDecision{
		Metered: d.metered, Allowed: d.allowed, Cost: d.cost.String(),
		Source: d.source, CheckedAt: time.Now(),
	})
}

// waitMeteredGate blocks while a full payload download must pause on a
// metered link. It logs the pause once per pause episode, re-checks every
// meteredPollInterval, and honors setup cancellation so the operator can
// abort instead of waiting. Returns nil when downloads may proceed.
func waitMeteredGate() error {
	for {
		d := evaluateMeteredPolicy()
		recordMeteredDecision(d)
		if !d.metered || d.allowed {
			return nil
		}
		ui := getUI()
		ui.setStatus("Waiting for an unmetered network connection... (allow in settings if this is wrong)")
		logf("payload download paused: Windows reports a %s-cost (metered) connection; "+
			"waiting, re-checking every %s. Allow metered downloads in Settings or with -allow-metered.",
			d.cost, meteredPollInterval)
		if err := sleepDuringSetup(meteredPollInterval); err != nil {
			return err
		}
	}
}

// describeMeteredGate renders the one-time startup provenance line.
func describeMeteredGate(metered bool, allowed bool, source string) string {
	if source == "nonwindows-default" {
		return "metered policy: platform hint unavailable on this OS; downloads never pause"
	}
	switch {
	case allowed:
		return "metered policy: operator allows downloads on metered links"
	case metered:
		return fmt.Sprintf("metered policy: link is metered now; payload downloads will pause (%s)", source)
	default:
		return fmt.Sprintf("metered policy: link is unmetered; payload downloads proceed (%s)", source)
	}
}

// meteredPollInterval is how often the gate re-checks the link while
// paused. A var so tests can shrink it without slowing the suite.
var meteredPollInterval = 30 * time.Second
