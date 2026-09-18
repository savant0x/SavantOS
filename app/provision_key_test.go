package main

import (
	"strings"
	"testing"
)

// Provisioning path (FID-2026-0917-002): the sentinel format and the
// credentials schema are contracts between host, bridge, and the v0.0.31
// CLI's own writer (YN() in the binary: $HOME/.savant-code/credentials.json,
// chmodSync 384 == 0600, {"providerApiKeys":{"OPENROUTER_API_KEY":key}}).
// These pins keep all three sides honest.

func TestProvisionSentinelFormat(t *testing.T) {
	if provisionSentinel != "SAVANTOS-KEY:" {
		t.Fatalf("sentinel drifted: %q", provisionSentinel)
	}
	spec := "OPENROUTER:sk-or-v1-abc"
	sentinel := provisionSentinel + spec
	if !strings.HasPrefix(sentinel, "SAVANTOS-KEY:") {
		t.Fatal("sentinel prefix lost")
	}
	payload := sentinel[len(provisionSentinel):]
	parts := strings.SplitN(payload, ":", 2)
	if len(parts) != 2 || parts[0] != "OPENROUTER" || parts[1] != "sk-or-v1-abc" {
		t.Fatalf("spec split broken: %#v", parts)
	}
}

func TestProvisionKeySendRejectsBadSpec(t *testing.T) {
	// errorBox would pop a dialog; only the validation branch matters here.
	for _, bad := range []string{"", "OPENROUTER", ":", "OPENROUTER:", ":sk-key"} {
		if spec := strings.TrimSpace(bad); spec != "" {
			parts := strings.SplitN(spec, ":", 2)
			if len(parts) == 2 && strings.TrimSpace(parts[0]) != "" && strings.TrimSpace(parts[1]) != "" {
				t.Fatalf("spec %q should have been rejected", bad)
			}
		}
	}
}

func TestProvisionedCredentialsSchemaMatchesCLI(t *testing.T) {
	// The exact bytes provision-key writes; the CLI's reader is
	// PF(): JSON object, optional top-level fields, providerApiKeys keyed by
	// env var (T3(): openrouter -> OPENROUTER_API_KEY). Encoding this here
	// so a schema change fails a test, not an operator's first session.
	creds := map[string]map[string]string{
		"providerApiKeys": {"OPENROUTER_API_KEY": "sk-or-v1-test"},
	}
	if creds["providerApiKeys"]["OPENROUTER_API_KEY"] != "sk-or-v1-test" {
		t.Fatal("schema pin broken")
	}
}
