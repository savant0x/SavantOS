//go:build windows

package main

// Windows wiring for pre-boot phase tracking (FID-2026-0916-001 H2): the
// core in phase_core.go is platform-neutral and unit-tested; this file
// connects it to logf, the splash status line, the -headless flag, and the
// modal-dialog discipline (D3/D4). Lives under the windows tag because logf
// and the progressUI are windows-only.

import (
	"fmt"
)

// preboot is the process-wide tracker; the watchdog goroutine starts on the
// first phaseEnter and retires at enterQemu.
var preboot = newPhaseCore(
	func(line string) { logf("%s", line) },
	func(text string) { getUI().setStatus("%s", text) },
)

// phaseEnter records a phase transition (log line + splash mirror + watchdog
// anchor reset). Call it immediately before every pre-boot phase begins.
func phaseEnter(name string) { preboot.enter(name) }

// phaseNote logs a mid-phase outcome without changing the phase.
func phaseNote(format string, a ...any) { preboot.note(format, a...) }

// phaseEnterQemu is the terminal transition; the watchdog retires after it.
func phaseEnterQemu() { preboot.enterQemu() }

// modalFatal is the D3 gate for dialogs with no safe default: under
// -headless it refuses loudly with the current phase instead of dangling
// on a dialog nobody can see.
func modalFatal(what string, format string, a ...any) {
	if headlessMode.Load() {
		fatal("%s (headless, no dialog available; current phase: %s): %s",
			what, phaseLabel(preboot.currentPhase()), fmt.Sprintf(format, a...))
	}
	// Interactive path: the caller shows its dialog as usual. This helper
	// only exists so call sites can express "no headless default" at the
	// top; see the -fresh confirm at data_location_windows.go for usage.
}

// headlessRefuse is for interactive-only flows that must not proceed at all
// under -headless (no safe default exists): log the refusal and report it.
func headlessRefuse(what string) bool {
	if headlessMode.Load() {
		logf("headless: refusing %s - no non-interactive default", what)
		return true
	}
	return false
}
