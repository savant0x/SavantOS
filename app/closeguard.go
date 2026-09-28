//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

// Closing the VM window must not hard-kill a running OS (it did: SDL's default
// close quits QEMU instantly - unsaved work in the guest, gone, no questions).
// QEMU now launches with window-close=off so the X does nothing by itself; a
// low-level mouse hook spots clicks on the caption's close button (the window
// itself reports what's under the cursor via WM_NCHITTEST) and the keyboard
// hook catches Alt+F4. Both funnel into one confirmation; Yes performs a
// GRACEFUL guest shutdown over QMP - autologin makes the next start seamless.

var (
	qemuHwnd            atomic.Uintptr // current VM window, set by the title enforcer
	confirmQuit         = make(chan struct{}, 1)
	confirmOpen         atomic.Bool
	procWindowFromPoint = user32.NewProc("WindowFromPoint")
)

const (
	whMouseLL       = 14
	wmLbuttondown   = 0x0201
	htCloseBtn      = 20
	vkF4            = 0x73
	mbDefbutton2    = 0x100
	mbSetForeground = 0x10000
	mbTopmost       = 0x40000
	// mbYesNo, mbIconQuestion, idYes: setup.go
)

// mouseHookCallback swallows left-clicks on the VM window's close button and
// asks for confirmation instead. Runs on the shared hook thread.
func mouseHookCallback(nCode, wParam, lParam uintptr) uintptr {
	if int32(nCode) >= 0 && wParam == wmLbuttondown {
		if hwnd := qemuHwnd.Load(); hwnd != 0 {
			pt := *(*[2]int32)(unsafe.Pointer(lParam)) // MSLLHOOKSTRUCT.pt
			packed := uintptr(uint64(uint32(pt[1]))<<32 | uint64(uint32(pt[0])))
			if under, _, _ := procWindowFromPoint.Call(packed); under == hwnd {
				lp := uintptr(uint32(pt[0])&0xFFFF | uint32(pt[1])<<16)
				if ht, _, _ := procSendMessageW.Call(hwnd, wmNchittest, 0, lp); ht == htCloseBtn {
					requestQuitConfirm()
					return 1 // swallow the click
				}
			}
		}
	}
	r, _, _ := procCallNextHookEx.Call(0, nCode, wParam, lParam)
	return r
}

func requestQuitConfirm() {
	select {
	case confirmQuit <- struct{}{}:
	default:
	}
}

// runCloseGuard owns the confirmation dialog and the bounded close ladder
// (FID-2026-0915-002): one confirmed close always drives the guest down -
// graceful first, escalated second, forced stop last. The guest's power
// button handler can silently drop the event, so the launcher is authoritative.
func runCloseGuard(forwards []portForward) {
	text, _ := syscall.UTF16PtrFromString("Shut down SavantOS?\n\nAnything unsaved inside SavantOS will be lost.")
	caption, _ := syscall.UTF16PtrFromString(appTitle)
	var closeStarted atomic.Bool
	for range confirmQuit {
		if confirmOpen.Swap(true) {
			continue // dialog already up
		}
		// Owned by the VM window + SETFOREGROUND, or the dialog opens BEHIND
		// the (foreground, topmost-ish) SDL window it is asking about.
		r, _, _ := procMessageBoxW.Call(qemuHwnd.Load(), uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(caption)),
			mbYesNo|mbIconQuestion|mbDefbutton2|mbTopmost|mbSetForeground)
		if r == idYes {
			logf("close confirmed - graceful guest shutdown")
			if !closeStarted.Swap(true) {
				// startCloseLadder, not `go runCloseLadder`: the exit path
				// waits on this ladder's verdict, so it must be registered
				// as in flight before the goroutine can finish.
				startCloseLadder(closeLadderOps{
					powerdown:    qmpPowerdown,
					stillRunning: closeGuestStillRunning,
					escalate:     sshPoweroffEscalation(forwards),
					forceStop:    forceStopQemu,
					logf:         logf,
				}, defaultCloseLadderTimings)
			}
		}
		confirmOpen.Store(false)
	}
}

// qmpPowerdown sends the graceful ACPI power button over QMP.
func qmpPowerdown() error {
	c := qmpConnect(qmpToolsPort, 8*time.Second)
	if c == nil {
		return fmt.Errorf("QMP tools port %d not answering", qmpToolsPort)
	}
	defer c.close()
	return c.writeLine(`{"execute":"system_powerdown"}`)
}

// closeGuestStillRunning reports whether the guest has NOT started going
// down. Ground truth is the supervisor's QEMU pid plus QMP query-status: an
// exited QEMU or an explicit shutdown status reads as down; a quiet monitor
// on a live process reads as still up so the ladder keeps escalating.
func closeGuestStillRunning() bool {
	if qemuPid.Load() == 0 {
		return false
	}
	c := qmpConnect(qmpToolsPort, 3*time.Second)
	if c == nil {
		return true
	}
	defer c.close()
	if err := c.writeLine(`{"execute":"query-status"}`); err != nil {
		return true
	}
	lines := c.readLines()
	deadline := time.After(3 * time.Second)
	for {
		select {
		case line, ok := <-lines:
			if !ok {
				return true
			}
			if !strings.Contains(line, `"return"`) {
				continue // greeting or async event
			}
			// Only an explicit shutdown status counts as "going down"; a
			// guest-panicked or wedged guest keeps the ladder escalating.
			return !strings.Contains(line, `"status":"shutdown"`)
		case <-deadline:
			return true
		}
	}
}

// forceStopQemu is the confirmed close's final fallback (the waitExit-class
// kill): the supervisor reaps the process and finishes its bookkeeping.
func forceStopQemu() {
	if pid := qemuPid.Load(); pid != 0 {
		if p, err := os.FindProcess(int(pid)); err == nil {
			p.Kill()
		}
	}
}

// sshPoweroffEscalation returns the ladder's privileged escalation over the
// session's ssh plane, or nil when there is none (no forward to the guest's
// sshd). `systemctl poweroff -i` ignores inhibitor locks: PowerDevil's
// handle-power-key block inhibitor is exactly what dropped the original
// close. The guest account is the factory's (build-spec guest.username); the
// factory polkit rule (50-savantos-power.rules, FID-2026-0928-001) grants it
// the power-off action family, since logind authorizes this call through
// polkit rather than sudoers.
func sshPoweroffEscalation(forwards []portForward) func() error {
	port := sshHostPort(forwards)
	if port == 0 {
		return nil
	}
	return func() error {
		cmd := exec.Command("ssh",
			"-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
			"-o", "ConnectTimeout=5", "-p", strconv.Itoa(port),
			"savant@127.0.0.1", "systemctl poweroff -i")
		// A windowsgui parent must not flash a console window.
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000 /* CREATE_NO_WINDOW */}
		out, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("ssh poweroff: %v (%s)", err, strings.TrimSpace(string(out)))
		}
		return nil
	}
}
