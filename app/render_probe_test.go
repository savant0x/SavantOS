package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRenderProbeRoundTrip(t *testing.T) {
	dir := t.TempDir()
	if p, err := loadRenderProbe(dir); err != nil || p != nil {
		t.Fatalf("missing probe should be nil, got %v %v", p, err)
	}
	now := time.Date(2026, 9, 5, 12, 0, 0, 0, time.UTC)
	want := renderProbe{Result: renderCPU, RuntimeID: "sha256:abc", DisplayDriver: "Intel=31.0.1", RecordedAt: now}
	if err := saveRenderProbe(dir, want); err != nil {
		t.Fatal(err)
	}
	got, err := loadRenderProbe(dir)
	if err != nil || got == nil || got.Schema != 1 || got.Result != renderCPU || got.RuntimeID != want.RuntimeID || !got.RecordedAt.Equal(now) {
		t.Fatalf("round trip mismatch: %+v %v", got, err)
	}
	if err := os.WriteFile(filepath.Join(dir, renderProbeFilename), []byte(`{"schema":1,"result":"maybe"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadRenderProbe(dir); err == nil {
		t.Fatal("unknown result must be rejected")
	}
}

// TestStartWithGPUGuardsTheAutoDefault pins the P0 guard (FID-2026-0917-001):
// auto (and any unrecognized mode) boots CPU unconditionally, because the
// wedge strikes after a successful boot and no probe memory can protect the
// desktop. Only an explicit gpu choice boots GPU.
func TestStartWithGPUGuardsTheAutoDefault(t *testing.T) {
	cases := []struct {
		name           string
		mode           string
		wantGPU        bool
		reasonContains []string
	}{
		{"auto is guarded to cpu", renderAuto, false, []string{"CPU rendering", "FID-2026-0917-001"}},
		{"empty mode is guarded to cpu", "", false, []string{"CPU rendering", "FID-2026-0917-001"}},
		{"forced gpu boots gpu", renderGPU, true, []string{"GPU rendering chosen"}},
		{"forced cpu boots cpu", renderCPU, false, []string{"CPU rendering chosen"}},
	}
	for _, c := range cases {
		gpu, reason := startWithGPU(c.mode)
		if gpu != c.wantGPU {
			t.Errorf("%s: got gpu=%v (reason %q), want gpu=%v", c.name, gpu, reason, c.wantGPU)
		}
		for _, want := range c.reasonContains {
			if !strings.Contains(reason, want) {
				t.Errorf("%s: reason %q does not contain %q", c.name, reason, want)
			}
		}
	}
}

func TestKeepUpdatedRuntimeOnlyAfterACPUResult(t *testing.T) {
	if keepUpdatedRuntimeOnCPU(nil) {
		t.Fatal("no history must roll the runtime back")
	}
	if keepUpdatedRuntimeOnCPU(&renderProbe{Result: renderGPU}) {
		t.Fatal("a working GPU path must roll the runtime back")
	}
	if !keepUpdatedRuntimeOnCPU(&renderProbe{Result: renderCPU, RuntimeID: "old"}) {
		t.Fatal("a CPU-only machine must keep the updated runtime")
	}
}

func TestParseRenderMode(t *testing.T) {
	for input, want := range map[string]string{"": renderAuto, " Auto ": renderAuto, "GPU": renderGPU, "cpu": renderCPU} {
		if got, err := parseRenderMode(input); err != nil || got != want {
			t.Errorf("%q: got %q %v, want %q", input, got, err, want)
		}
	}
	if _, err := parseRenderMode("software"); err == nil {
		t.Fatal("unknown mode must be rejected")
	}
}

func TestRuntimeIdentityPrefersTheReceiptHash(t *testing.T) {
	root := t.TempDir()
	if runtimeIdentity(root) != "" {
		t.Fatal("missing runtime must have no identity")
	}
	bin := filepath.Join(root, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(bin, "qemu-system-x86_64w.exe"), []byte("qemu"), 0o644); err != nil {
		t.Fatal(err)
	}
	if id := runtimeIdentity(root); !strings.HasPrefix(id, "stat:4:") {
		t.Fatalf("receipt-less runtime should use size and mtime, got %q", id)
	}
	sum := strings.Repeat("ab", 32)
	receipt := `{"schema":1,"release":"r","manifestSHA256":"` + sum + `","archiveSHA256":"` + sum + `","executable":{"sha256":"` + sum + `","size":4,"modTimeUnixNano":1}}`
	if err := os.WriteFile(filepath.Join(root, runtimeReceiptFilename), []byte(receipt), 0o644); err != nil {
		t.Fatal(err)
	}
	if id := runtimeIdentity(root); id != "sha256:"+sum {
		t.Fatalf("receipt hash expected, got %q", id)
	}
}
