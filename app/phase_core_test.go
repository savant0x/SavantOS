package main

// Tests for the pre-boot phase core (FID-2026-0916-001 G5). Platform-
// neutral on purpose: the watchdog logic must be provable on any OS. The
// windows-side wiring (logf/splash/headless) is exercised on Windows and
// by G5's live-boot evidence.

import (
	"strings"
	"sync"
	"testing"
	"time"
)

type lineCollector struct {
	mu    sync.Mutex
	lines []string
}

func (l *lineCollector) emit(line string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.lines = append(l.lines, line)
}

func (l *lineCollector) snapshot() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]string(nil), l.lines...)
}

func (l *lineCollector) joined() string { return strings.Join(l.snapshot(), "\n") }

func withFastWatchdog(t *testing.T) {
	t.Helper()
	oldWarn, oldHint, oldPoll := phaseWarnAfter, phaseHintAfter, phasePollEvery
	phaseWarnAfter = 30 * time.Millisecond
	phaseHintAfter = 60 * time.Millisecond
	phasePollEvery = 10 * time.Millisecond
	t.Cleanup(func() {
		phaseWarnAfter, phaseHintAfter, phasePollEvery = oldWarn, oldHint, oldPoll
	})
}

func TestPhaseTransitionsAreLoggedAndMirrored(t *testing.T) {
	var (
		col      lineCollector
		splashMu sync.Mutex
		splash   []string
	)
	core := newPhaseCore(col.emit, func(text string) {
		splashMu.Lock()
		splash = append(splash, text)
		splashMu.Unlock()
	})
	core.enter("settings")
	core.enter("update-check")
	core.note("update check outcome: none due")
	core.enterQemu()

	got := col.joined()
	for _, want := range []string{
		"phase: settings",
		"phase: update-check",
		"phase: update check outcome: none due",
		"phase: qemu",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	splashMu.Lock()
	defer splashMu.Unlock()
	if len(splash) != 3 { // two enters + qemu, not the note
		t.Fatalf("splash mirror count = %d, want 3: %v", len(splash), splash)
	}
	if !strings.Contains(splash[0], "loading settings") {
		t.Errorf("splash[0] = %q, want phaseLabel text", splash[0])
	}
}

func TestWatchdogWarnsThenHintsAndRetires(t *testing.T) {
	withFastWatchdog(t)
	var col lineCollector
	core := newPhaseCore(col.emit, nil)
	core.enter("runtime") // starts the watchdog

	// Hold the phase past warn and hint thresholds.
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		got := col.joined()
		if strings.Contains(got, "preboot-watchdog") &&
			strings.Contains(got, "no phase progress") &&
			strings.Contains(got, "-headless") {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	got := col.joined()
	if !strings.Contains(got, "(current phase: runtime)") {
		t.Errorf("watchdog did not name the held phase:\n%s", got)
	}
	if !strings.Contains(got, "headless runs avoid dialogs") {
		t.Errorf("hint level missing the dialog hint:\n%s", got)
	}

	// Terminal transition retires the watchdog: no more lines after it.
	before := len(col.snapshot())
	core.enterQemu()
	time.Sleep(120 * time.Millisecond)
	after := col.snapshot()
	for _, line := range after[before+1:] { // skip the qemu phase line itself
		if strings.Contains(line, "preboot-watchdog") {
			t.Errorf("watchdog kept talking after qemu: %q", line)
		}
	}
}

func TestWatchdogRateLimitsPerLevel(t *testing.T) {
	withFastWatchdog(t)
	var col lineCollector
	core := newPhaseCore(col.emit, nil)
	core.enter("guest-ensure")

	// One silence stretch must yield at most one warn and one hint even
	// after several poll cycles.
	time.Sleep(150 * time.Millisecond)
	warns, hints := 0, 0
	for _, line := range col.snapshot() {
		switch {
		case strings.Contains(line, "still working or waiting"):
			warns++
		case strings.Contains(line, "headless runs avoid dialogs"):
			hints++
		}
	}
	if warns > 1 || hints > 1 {
		t.Errorf("rate limit failed: %d warns, %d hints in one stretch", warns, hints)
	}
}

func TestCurrentPhaseTracking(t *testing.T) {
	core := newPhaseCore(func(string) {}, nil)
	if got := core.currentPhase(); got != "" {
		t.Errorf("before any transition currentPhase = %q, want empty", got)
	}
	core.enter("whp-check")
	if got := core.currentPhase(); got != "whp-check" {
		t.Errorf("currentPhase = %q, want whp-check", got)
	}
}

func TestPhaseLabelsCoverAllPhases(t *testing.T) {
	labels := map[string]string{
		"starting":         "starting", // the one label that matches its key by design
		"settings":         "loading settings",
		"share-validation": "checking the shared folder",
		"update-check":     "checking for updates",
		"whp-check":        "checking virtualization",
		"provision-mode":   "first-boot options",
		"runtime":          "preparing the graphics engine",
		"render-decision":  "choosing a rendering path",
		"guest-ensure":     "preparing SavantOS",
		"qemu":             "starting the virtual machine",
	}
	for name, want := range labels {
		if got := phaseLabel(name); got != want {
			t.Errorf("phaseLabel(%q) = %q, want %q", name, got, want)
		}
	}
}
