package main

// Phase-tracking core (FID-2026-0916-001 H2, D2). Platform-neutral so the
// watchdog logic is unit-testable on any OS: emitters are injected, and the
// windows side (phase.go) wires them to logf and the splash status line.
//
// The silent-stall incident family (FID-2026-0915-002) had no attributable
// evidence: a launcher waiting forever on a modal nobody can see, with no
// phase names in vm/shell.log. D2 makes every pre-boot phase transition emit
// a log line and runs a watchdog that speaks up during silence. It never
// auto-kills: a provision interrupted mid-download is destructive, so
// visibility is the whole job.

import (
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

// headlessMode (D3): set from -headless before any dialog-capable step
// runs. Every modal entry point checks it and takes its non-interactive
// default (or fatals when no safe default exists), logging the choice.
var headlessMode atomic.Bool

// modalChoice is the D3 gate for two-way dialogs: under -headless the
// non-interactive default is taken and logged; otherwise the interactive
// path runs. Evidence goes through the tracker's emit (logf on windows),
// so the decision is attributable in vm/shell.log either way.
func modalChoice(headlessDefault bool, what string, interactive func() bool) bool {
	if headlessMode.Load() {
		preboot.emit("headless: " + what + " -> " + fmt.Sprint(headlessDefault))
		return headlessDefault
	}
	return interactive()
}

// modalChoice2 is the D3 gate for two-value dialogs (shortcuts: primary,
// secondary) — same contract as modalChoice with a pair default.
func modalChoice2(headlessPrimary, headlessSecondary bool, what string, interactive func() (bool, bool)) (bool, bool) {
	if headlessMode.Load() {
		preboot.emit(fmt.Sprintf("headless: %s -> (%v, %v)", what, headlessPrimary, headlessSecondary))
		return headlessPrimary, headlessSecondary
	}
	return interactive()
}

// Phase names are stable strings: they appear in vm/shell.log, in FID
// evidence, and in operator bug reports. Do not reword them casually.
const (
	phaseStarting       = "starting"
	phaseSettings       = "settings"
	phaseShare          = "share-validation"
	phaseUpdateCheck    = "update-check"
	phaseWHPCheck       = "whp-check"
	phaseProvisionMode  = "provision-mode"
	phaseRuntime        = "runtime"
	phaseRenderDecision = "render-decision"
	phaseGuestEnsure    = "guest-ensure"
)

// Thresholds are vars so tests can shrink them; production values are set
// by phase.go's init on the windows side (90 s warn, 5 min dialog hint).
var (
	phaseWarnAfter = 90 * time.Second
	phaseHintAfter = 5 * time.Minute
	phasePollEvery = 15 * time.Second
	// Repeat intervals per level: a held phase warns again every 90 s until
	// the hint level takes over at 5 min, then hints every 5 min.
	phaseWarnEvery = 90 * time.Second
	phaseHintEvery = 5 * time.Minute
)

// phaseCore records the current pre-boot phase and drives the watchdog.
// enterQemu is the terminal transition: after QEMU spawns, the guest and
// the QEMU supervisor produce their own evidence, so the watchdog retires.
type phaseCore struct {
	mu         sync.Mutex
	phase      string
	since      time.Time
	lastWarnAt time.Time
	lastHintAt time.Time
	qemuUp     bool
	started    bool
	emit       func(line string) // log sink (required)
	status     func(text string) // splash mirror (optional, nil on tests)
	stop       chan struct{}
	stopOnce   sync.Once
}

func newPhaseCore(emit func(line string), status func(text string)) *phaseCore {
	return &phaseCore{
		emit:   emit,
		status: status,
		stop:   make(chan struct{}),
	}
}

// enter records a phase transition: one log line, one splash update, and a
// watchdog anchor reset. Cheap enough to call before every phase.
func (c *phaseCore) enter(name string) {
	c.mu.Lock()
	if !c.started {
		c.started = true
		go c.watch()
	}
	c.phase = name
	c.since = time.Now()
	c.mu.Unlock()
	c.emit("phase: " + name)
	if c.status != nil {
		c.status("SavantOS: " + phaseLabel(name))
	}
}

// note logs a mid-phase outcome without changing the phase (update-check
// results, skips). The watchdog anchor is left alone: the phase itself is
// still in progress.
func (c *phaseCore) note(format string, a ...any) {
	c.emit("phase: " + fmt.Sprintf(format, a...))
}

// enterQemu is the terminal transition; the watchdog retires after it.
func (c *phaseCore) enterQemu() {
	c.mu.Lock()
	c.qemuUp = true
	c.phase = "qemu"
	c.since = time.Now()
	c.mu.Unlock()
	c.emit("phase: qemu")
	if c.status != nil {
		c.status("SavantOS: starting the virtual machine")
	}
	c.stopOnce.Do(func() { close(c.stop) })
}

// warnBoth surfaces a watchdog warning on the log and the splash (D4:
// heartbeat warnings must be visible where the operator is looking).
func (c *phaseCore) warnBoth(logText, splashText string) {
	c.emit("preboot-watchdog: " + logText)
	if c.status != nil {
		c.status("SavantOS: " + splashText)
	}
}

// currentPhase reports the active phase name for diagnostics (empty before
// the first transition).
func (c *phaseCore) currentPhase() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.phase
}

func (c *phaseCore) watch() {
	tick := time.NewTicker(phasePollEvery)
	defer tick.Stop()
	for {
		select {
		case <-c.stop:
			return
		case <-tick.C:
			c.mu.Lock()
			phase, since, up := c.phase, c.since, c.qemuUp
			c.mu.Unlock()
			if up || phase == "" {
				continue
			}
			silent := time.Since(since)
			now := time.Now()
			if silent >= phaseHintAfter {
				if now.Sub(c.lastHint()) >= phaseHintEvery {
					c.warnBoth("no phase progress for "+silent.Round(time.Second).String()+
						" (current phase: "+phase+"). If a dialog is open, it may be hidden behind another window; -headless runs avoid dialogs entirely. The launcher keeps waiting; kill it if this phase cannot finish.",
						"still waiting: "+phaseLabel(phase)+" ("+silent.Round(time.Second).String()+")")
					c.setLastHint(now)
				}
				continue
			}
			if silent >= phaseWarnAfter && now.Sub(c.lastWarn()) >= phaseWarnEvery {
				c.warnBoth("no phase progress for "+silent.Round(time.Second).String()+
					" (current phase: "+phase+") - still working or waiting",
					"still working: "+phaseLabel(phase)+" ("+silent.Round(time.Second).String()+")")
				c.setLastWarn(now)
			}
		}
	}
}

func (c *phaseCore) lastWarn() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.lastWarnAt
}

func (c *phaseCore) setLastWarn(t time.Time) {
	c.mu.Lock()
	c.lastWarnAt = t
	c.mu.Unlock()
}

func (c *phaseCore) lastHint() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.lastHintAt
}

func (c *phaseCore) setLastHint(t time.Time) {
	c.mu.Lock()
	c.lastHintAt = t
	c.mu.Unlock()
}

// phaseLabel renders the stable phase name for the splash status line (D4).
func phaseLabel(name string) string {
	switch name {
	case "starting":
		return "starting"
	case "settings":
		return "loading settings"
	case "share-validation":
		return "checking the shared folder"
	case "update-check":
		return "checking for updates"
	case "whp-check":
		return "checking virtualization"
	case "provision-mode":
		return "first-boot options"
	case "runtime":
		return "preparing the graphics engine"
	case "render-decision":
		return "choosing a rendering path"
	case "guest-ensure":
		return "preparing SavantOS"
	case "qemu":
		return "starting the virtual machine"
	}
	return name
}
