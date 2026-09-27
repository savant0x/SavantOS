package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPayloadOverridesActive(t *testing.T) {
	const (
		release = "https://github.com/savant0x/SavantOS/releases/download/v0.0.1"
		sums    = "3b106a44fa0324dfc88dd674e9f3758b4e9d2e27c066673fdb04c9c5eb357185"
	)
	cases := []struct {
		name                            string
		rel, s, runtimeRel, runtimeSums string
		want                            bool
	}{
		{"shipped pins", release, sums, release, sums, false},
		{"blank runtime pins fall back to release", release, sums, "", "", false},
		{"trailing slash is the same release", release + "/", sums, release, sums, false},
		{"custom release URL", "http://127.0.0.1:8765", sums, release, sums, true},
		{"custom sums digest", release, strings.Repeat("a", 64), release, sums, true},
		{"custom runtime release", release, sums, "http://127.0.0.1:9000", sums, true},
		{"custom runtime digest", release, sums, release, strings.Repeat("b", 64), true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := payloadOverridesActive(tc.rel, tc.s, tc.runtimeRel, tc.runtimeSums); got != tc.want {
				t.Fatalf("payloadOverridesActive = %v, want %v", got, tc.want)
			}
		})
	}
}

func writeDevAnchor(t *testing.T, dir, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, devAnchorFilename), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeGuestPayload(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, "guest"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "guest", "rootfs.ext4"), []byte("payload"), 0o644); err != nil {
		t.Fatal(err)
	}
}

// TestOverrideTargetGuardTable is gate G1 of FID-2026-0916-001: the exact
// allow/refuse table, including the 11:36 incident shape (overrides on a
// launcher-resolved directory) and the damaged/partial/runtime-only cases the
// stage-2 acceptance names.
func TestOverrideTargetGuardTable(t *testing.T) {
	const goodAnchor = `{"kind": "savantos-dev-anchor", "version": 1}`
	cases := []struct {
		name        string
		overrides   bool
		explicitDir bool
		setup       func(t *testing.T, dir string)
		wantRefused bool
	}{
		{"G1: no overrides on a resolved dir with an install", false, false, writeGuestPayload, false},
		{"G1: overrides + launcher-resolved dir (the 11:36 incident shape)", true, false, writeGuestPayload, true},
		{"G1: overrides + resolved fresh dir", true, false, nil, true},
		{"G1: overrides + explicit dir with unanchored install", true, true, writeGuestPayload, true},
		{"G1: overrides + explicit dir with dev anchor", true, true, func(t *testing.T, dir string) {
			writeGuestPayload(t, dir)
			writeDevAnchor(t, dir, goodAnchor)
		}, false},
		{"G1: overrides + explicit fresh dir", true, true, nil, false},
		{"damaged/partial install is still an install", true, true, func(t *testing.T, dir string) {
			// A crashed provision: guest tree without any receipt.
			if err := os.MkdirAll(filepath.Join(dir, "guest"), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, "guest", "rootfs.ext4.part"), []byte("partial"), 0o644); err != nil {
				t.Fatal(err)
			}
		}, true},
		{"runtime-only dir carries no guest install", true, true, func(t *testing.T, dir string) {
			if err := os.MkdirAll(filepath.Join(dir, "runtime", "bin"), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, "runtime", "bin", "qemu-system-x86_64w.exe"), []byte("qemu"), 0o755); err != nil {
				t.Fatal(err)
			}
		}, false},
		{"empty guest dir is still no install", true, true, func(t *testing.T, dir string) {
			if err := os.MkdirAll(filepath.Join(dir, "guest"), 0o755); err != nil {
				t.Fatal(err)
			}
		}, false},
		{"malformed anchor counts as absent", true, true, func(t *testing.T, dir string) {
			writeGuestPayload(t, dir)
			writeDevAnchor(t, dir, "not json")
		}, true},
		{"anchor with unknown fields counts as absent", true, true, func(t *testing.T, dir string) {
			writeGuestPayload(t, dir)
			writeDevAnchor(t, dir, `{"kind": "savantos-dev-anchor", "version": 1, "extra": true}`)
		}, true},
		{"anchor with wrong kind counts as absent", true, true, func(t *testing.T, dir string) {
			writeGuestPayload(t, dir)
			writeDevAnchor(t, dir, `{"kind": "other", "version": 1}`)
		}, true},
		{"anchor with wrong version counts as absent", true, true, func(t *testing.T, dir string) {
			writeGuestPayload(t, dir)
			writeDevAnchor(t, dir, `{"kind": "savantos-dev-anchor", "version": 2}`)
		}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if tc.setup != nil {
				tc.setup(t, dir)
			}
			err := checkPayloadOverrideTarget(tc.overrides, tc.explicitDir, dir)
			if tc.wantRefused {
				if err == nil {
					t.Fatal("override target was allowed; want refusal")
				}
				// Every refusal names the resolved dir and the remedy (D1).
				if !strings.Contains(err.Error(), dir) {
					t.Fatalf("refusal does not name the resolved dir: %v", err)
				}
				if !strings.Contains(err.Error(), "-dir") && !strings.Contains(err.Error(), "dev-anchor.json") {
					t.Fatalf("refusal does not name a remedy: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("override target refused: %v", err)
			}
		})
	}
}

func TestDevAnchorValidation(t *testing.T) {
	dir := t.TempDir()
	if devAnchorPresent(dir) {
		t.Fatal("missing anchor reported present")
	}
	writeDevAnchor(t, dir, `{"kind": "savantos-dev-anchor", "version": 1}`)
	if !devAnchorPresent(dir) {
		t.Fatal("well-formed anchor reported absent")
	}
}
