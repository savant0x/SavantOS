//go:build windows

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestProbeAVX2SupportLive pins the probe's contract against the real API:
// the answer is exactly one of the three states, and the OS's yes/no is
// reported verbatim (never guessed).
func TestProbeAVX2SupportLive(t *testing.T) {
	got := probeAVX2Support()
	switch {
	case got == "yes" || got == "no":
	case strings.HasPrefix(got, "unknown ("):
	default:
		t.Fatalf("probe answered %q, want yes/no/unknown(...)", got)
	}
}

// TestProbeVulkanSupportLive walks the real registry: the probe must always
// produce a describable outcome, and a registry failure must surface as
// "unknown", never as a fabricated driver fact.
func TestProbeVulkanSupportLive(t *testing.T) {
	probe := probeVulkanSupport()
	got := probe.describe()
	if got == "" {
		t.Fatal("describe returned an empty fact")
	}
	if probe.Error != "" && !strings.HasPrefix(got, "unknown (") {
		t.Fatalf("error %q must describe as unknown, got %q", probe.Error, got)
	}
	if probe.Error == "" && strings.HasPrefix(got, "unknown") {
		t.Fatalf("no error recorded but describe says %q", got)
	}
}

// TestReadVulkanManifestOversize pins the size bound: a manifest larger than
// maxVulkanManifestBytes is refused outright, never slurped whole and
// truncated after the fact (the behavior this replaced, which contradicted
// the bounded-read contract in capability.go).
func TestReadVulkanManifestOversize(t *testing.T) {
	path := filepath.Join(t.TempDir(), "oversize.json")
	oversize := append([]byte(`{"ICD":{"api_version":"1.3.280"}}`),
		bytes.Repeat([]byte(" "), maxVulkanManifestBytes+1)...)
	if err := os.WriteFile(path, oversize, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := readVulkanManifest(path); err == nil {
		t.Fatalf("a %d-byte manifest must be refused, not read", len(oversize))
	}
}

// TestReadVulkanManifestAtLimit pins the boundary itself, so the bound cannot
// drift off by one: exactly maxVulkanManifestBytes is readable and its
// api_version still parses.
func TestReadVulkanManifestAtLimit(t *testing.T) {
	body := []byte(`{"ICD":{"api_version":"1.3.280"}}`)
	pad := maxVulkanManifestBytes - len(body)
	if pad < 0 {
		t.Fatalf("fixture body (%d bytes) already exceeds the bound", len(body))
	}
	path := filepath.Join(t.TempDir(), "at-limit.json")
	if err := os.WriteFile(path, append(body, bytes.Repeat([]byte(" "), pad)...), 0o600); err != nil {
		t.Fatal(err)
	}
	data, err := readVulkanManifest(path)
	if err != nil {
		t.Fatalf("exactly %d bytes must read: %v", maxVulkanManifestBytes, err)
	}
	if len(data) != maxVulkanManifestBytes {
		t.Fatalf("read %d bytes, want %d", len(data), maxVulkanManifestBytes)
	}
	if got := parseVulkanICDAPIVersion(data); got != "1.3.280" {
		t.Fatalf("api_version within the bound must parse, got %q", got)
	}
}

// TestReadVulkanManifestMissing pins the unreadable case the probe tolerates
// by design: absence is an error here, and the caller leaves that driver's
// version unknown rather than disturbing a launch over a diagnostics fact.
func TestReadVulkanManifestMissing(t *testing.T) {
	if _, err := readVulkanManifest(filepath.Join(t.TempDir(), "absent.json")); err == nil {
		t.Fatal("a missing manifest must return an error")
	}
}
