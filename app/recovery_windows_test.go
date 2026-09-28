//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

// T1.2 regression lock (FID-2026-0916-001 D3 / FID-2026-0914-003 finding):
// -fresh on a directory with an existing disk reaches confirmResetBackup, and
// its headless branch must decide WITHOUT a dialog — a real MessageBoxW in the
// test process would hang until the run timeout, which is the failure mode
// these tests exist to catch. If the branch ever regresses to calling msgBox,
// TestHeadlessResetConfirmProceeds fails fast with an empty-earlyLog
// diagnostic instead of blocking.
func setHeadlessForTest(t *testing.T, on bool) {
	t.Helper()
	prev := headlessMode.Load()
	headlessMode.Store(on)
	t.Cleanup(func() { headlessMode.Store(prev) })
}

func TestHeadlessResetConfirmProceeds(t *testing.T) {
	setHeadlessForTest(t, true)
	configureSetupCancellation(false)
	t.Cleanup(func() { setupCancelPending.Store(false) })

	earlyLog = nil
	proceed, err := confirmResetBackup(t.TempDir())
	if err != nil {
		t.Fatalf("headless confirm returned error: %v", err)
	}
	if !proceed {
		t.Fatal("headless confirm did not proceed without the backup dialog")
	}
	found := false
	for _, line := range earlyLog {
		if strings.Contains(line, "headless: reset confirm -> proceed without full backup") {
			found = true
		}
	}
	if !found {
		t.Fatalf("decision line missing from earlyLog: %v", earlyLog)
	}
}

func TestHeadlessResetConfirmHonorsCancellation(t *testing.T) {
	setHeadlessForTest(t, true)
	configureSetupCancellation(false)
	t.Cleanup(func() { setupCancelPending.Store(false) })

	requestSetupCancel()
	earlyLog = nil
	proceed, err := confirmResetBackup(t.TempDir())
	if !errors.Is(err, errSetupCancelled) {
		t.Fatalf("cancelled confirm: err = %v, want errSetupCancelled", err)
	}
	if proceed {
		t.Fatal("cancelled headless confirm must not report proceed")
	}
}

func TestRestoredShortcutsTargetOnlyRestoredFolder(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "Restored guest with spaces")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := createRestoredLaunchers(dir); err != nil {
		t.Fatal(err)
	}
	const script = `$ErrorActionPreference='Stop'; $shell=New-Object -ComObject WScript.Shell; $links=@(foreach($name in @('Start SavantOS.lnk','Settings.lnk')){ $link=$shell.CreateShortcut((Join-Path $env:SAVANTOS_TEST_DIR $name)); [pscustomobject]@{Name=$name;Target=$link.TargetPath;Arguments=$link.Arguments;Directory=$link.WorkingDirectory} }); ConvertTo-Json -Compress -InputObject $links`

	cmd := exec.Command(system32("WindowsPowerShell\\v1.0\\powershell.exe"), "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.Env = append(os.Environ(), "SAVANTOS_TEST_DIR="+dir)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("reading shortcuts: %v: %s", err, strings.TrimSpace(string(out)))
	}
	var links []struct{ Name, Target, Arguments, Directory string }
	if err := json.Unmarshal(out, &links); err != nil {
		t.Fatalf("shortcut metadata: %v: %s", err, out)
	}
	if len(links) != 2 {
		t.Fatalf("shortcuts: %s", out)
	}
	for _, link := range links {
		// Windows Shell can expand 8.3 paths from the runner's temporary directory.
		// Compare file identity instead of treating equivalent paths as different.
		for _, pair := range [][2]string{{link.Target, filepath.Join(dir, stableLauncherName)}, {link.Directory, dir}} {
			actual, expected := pair[0], pair[1]
			got, err := os.Stat(actual)
			if err != nil {
				t.Fatalf("shortcut %s: %v", actual, err)
			}
			want, err := os.Stat(expected)
			if err != nil {
				t.Fatal(err)
			}
			if !os.SameFile(got, want) {
				t.Fatalf("shortcut %s points to %s, expected %s", link.Name, actual, expected)
			}
		}
		wantArgs := `-dir "` + dir + `"`
		if link.Name == "Settings.lnk" {
			wantArgs += " -settings"
		} else if link.Name != "Start SavantOS.lnk" {
			t.Fatalf("unexpected shortcut %q", link.Name)
		}
		if link.Arguments != wantArgs {
			t.Fatalf("shortcut arguments = %q, want %q", link.Arguments, wantArgs)
		}
	}

	if !shortcutOfferRecorded(dir) {
		t.Fatal("restored launch could offer to replace original shortcuts")
	}
}
