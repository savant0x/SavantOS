package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// Developer payload overrides aimed at a data directory the launcher resolved
// on its own replaced a production install once (FID-2026-0916-001 E1: a
// stray `-release http://127.0.0.1:8765 -sums-sha256 …` run followed the
// data-location pointer into the production directory and re-provisioned it
// before booting). This guard is the fail-closed refusal that incident
// demands: an override run may only update a data directory the caller named,
// and an existing install in a named directory is override territory only
// when dev tooling has anchored it.

const (
	// devAnchorFilename is the marker scripts/dev/dev-vm.sh init writes into
	// a data directory it owns. Production installs never carry one.
	devAnchorFilename = "dev-anchor.json"
	devAnchorKind     = "savantos-dev-anchor"
	devAnchorVersion  = 1
	maxDevAnchorBytes = 16 << 10
)

// devAnchor is the exact schema of the dev marker. Unknown fields, a wrong
// version, or a wrong kind make the anchor invalid, which fails toward
// refusal.
type devAnchor struct {
	Version int    `json:"version"`
	Kind    string `json:"kind"`
}

// payloadOverridesActive reports whether the run pins non-default payload
// sources (FID-2026-0916-001 E3: the escalation is a non-default release URL
// or digest). Blank runtime pins mean "follow the release pins", matching the
// flag normalization in main; anything else beyond the release pairing is
// caller-chosen too.
func payloadOverridesActive(release, sumsSHA256, runtimeRelease, runtimeSumsSHA256 string) bool {
	if !releaseLocationsEquivalent(release, defaultReleaseURL) ||
		normalizedSHA256(sumsSHA256) != normalizedSHA256(defaultSumsSHA256) {
		return true
	}
	if strings.TrimSpace(runtimeRelease) == "" {
		runtimeRelease = release
	}
	if strings.TrimSpace(runtimeSumsSHA256) == "" {
		runtimeSumsSHA256 = sumsSHA256
	}
	return !releaseLocationsEquivalent(runtimeRelease, release) ||
		normalizedSHA256(runtimeSumsSHA256) != normalizedSHA256(sumsSHA256)
}

// devAnchorPresent reports whether dir carries a well-formed dev anchor.
// Anything short of that is treated as absent.
func devAnchorPresent(dir string) bool {
	path := filepath.Join(dir, devAnchorFilename)
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxDevAnchorBytes {
		return false
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	dec := json.NewDecoder(strings.NewReader(string(data)))
	dec.DisallowUnknownFields()
	var anchor devAnchor
	if err := dec.Decode(&anchor); err != nil {
		return false
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return false
	}
	return anchor.Version == devAnchorVersion && anchor.Kind == devAnchorKind
}

// guestInstallPresent reports whether dir carries guest payload state: a
// verified install receipt, a half-provisioned tree, or anything else under
// guest/. An empty or missing guest directory is still "no install yet"; a
// runtime-only directory likewise carries no guest payload to protect.
func guestInstallPresent(dir string) (bool, error) {
	entries, err := os.ReadDir(filepath.Join(dir, "guest"))
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return len(entries) > 0, nil
}

// checkPayloadOverrideTarget is the D1 guard table (FID-2026-0916-001):
//
//	no overrides                       -> proceed (the production path is unchanged)
//	overrides + caller-named directory -> proceed with a dev anchor, or on a
//	                                     directory with no install yet
//	overrides + launcher-resolved dir  -> refuse outright
//
// explicitDir reports whether the caller named the directory (-dir, or the
// portable exe's own data folder); a pointer, default, or chooser resolution
// is never caller-named. Every refusal names the resolved directory and the
// remedy so the incident cannot end in a mystery.
func checkPayloadOverrideTarget(overrides, explicitDir bool, dir string) error {
	if !overrides {
		return nil
	}
	if !explicitDir {
		return fmt.Errorf("payload overrides (-release/-sums-sha256/-runtime-*) may not update %s: this data directory was resolved by SavantOS, not named by the caller\n\nRe-run with -dir naming a dev data directory (scripts/dev/dev-vm.sh init writes dev-anchor.json), or drop the overrides to use the production release", dir)
	}
	if devAnchorPresent(dir) {
		return nil
	}
	present, err := guestInstallPresent(dir)
	if err != nil {
		return fmt.Errorf("cannot inspect %s: %w", dir, err)
	}
	if !present {
		return nil
	}
	return fmt.Errorf("payload overrides (-release/-sums-sha256/-runtime-*) may not update %s: this data directory has an installed SavantOS and no dev anchor\n\nRun scripts/dev/dev-vm.sh init on dev data directories (writes dev-anchor.json), or drop the overrides", dir)
}
