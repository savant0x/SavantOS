package main

// Host capability probes (FID-2026-0914-002 steps 3b/3c): what the Windows
// graphics and CPU stack actually supports, carried by the render-probe
// record and the diagnostics facts. Detection only — nothing here gates a
// launch; the rendering policy lives in render_probe.go.

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// vulkanProbe is the outcome of walking the Vulkan installable-client-driver
// manifests (step 3b). Loader means the Vulkan loader DLL exists; the ICDs
// are the registered driver manifests; Error names a registry failure that
// is neither "absent" nor "readable".
type vulkanProbe struct {
	Loader bool
	ICDs   []vulkanICD
	Error  string
}

// vulkanICD is one driver manifest: where it was found and the Vulkan API
// version it declares. An unreadable or malformed manifest still counts as
// a registered driver with an unknown version — the probe reports what it
// saw rather than guessing.
type vulkanICD struct {
	Manifest   string
	APIVersion string
}

// maxVulkanManifestBytes bounds the manifest read in readVulkanManifest: the
// path comes from the registry, and a hostile or corrupt value must cost a
// bounded read and a parse failure, not an unbounded allocation.
const maxVulkanManifestBytes = 64 << 10

// parseVulkanICDAPIVersion extracts ICD.api_version from a manifest.
// Returns "" when the field is absent or the JSON is malformed: a manifest
// without a version still names a driver, so this is "unknown", not an error.
func parseVulkanICDAPIVersion(manifest []byte) string {
	var doc struct {
		ICD struct {
			APIVersion string `json:"api_version"`
		} `json:"ICD"`
	}
	if err := json.Unmarshal(manifest, &doc); err != nil {
		return ""
	}
	return strings.TrimSpace(doc.ICD.APIVersion)
}

// vulkanVersion is a parsed "major.minor(.patch)" API version.
type vulkanVersion struct {
	major, minor, patch int
}

// parseVulkanVersion accepts two- or three-part non-negative integer
// versions ("1.3", "1.3.280"); anything else is unparseable.
func parseVulkanVersion(version string) (vulkanVersion, bool) {
	parts := strings.Split(version, ".")
	if len(parts) < 2 || len(parts) > 3 {
		return vulkanVersion{}, false
	}
	var v vulkanVersion
	for i, part := range parts {
		n, err := strconv.Atoi(part)
		if err != nil || n < 0 {
			return vulkanVersion{}, false
		}
		switch i {
		case 0:
			v.major = n
		case 1:
			v.minor = n
		case 2:
			v.patch = n
		}
	}
	return v, true
}

// supports13 reports whether the version is Vulkan 1.3 or newer.
func (v vulkanVersion) supports13() bool {
	return v.major > 1 || (v.major == 1 && v.minor >= 3)
}

// less orders versions numerically; "1.10" sorts after "1.9".
func (v vulkanVersion) less(other vulkanVersion) bool {
	if v.major != other.major {
		return v.major < other.major
	}
	if v.minor != other.minor {
		return v.minor < other.minor
	}
	return v.patch < other.patch
}

// vulkanSupports13 reports whether a declared version string is Vulkan 1.3
// or newer. Unparseable versions are false: the probe asserts 1.3 only when
// it can actually read it.
func vulkanSupports13(version string) bool {
	v, ok := parseVulkanVersion(version)
	return ok && v.supports13()
}

// describe renders the probe as one stable fact string for the probe record
// and the diagnostics bundle. The states are total and mutually exclusive:
// every outcome maps to exactly one string.
func (p vulkanProbe) describe() string {
	if p.Error != "" {
		return "unknown (" + p.Error + ")"
	}
	bestVersion := ""
	var best vulkanVersion
	bestOK := false
	for _, icd := range p.ICDs {
		v, ok := parseVulkanVersion(icd.APIVersion)
		if !ok {
			continue
		}
		if !bestOK || best.less(v) {
			best, bestVersion, bestOK = v, icd.APIVersion, true
		}
	}
	switch {
	case bestOK && best.supports13():
		return fmt.Sprintf("%s via %d driver(s)", bestVersion, len(p.ICDs))
	case bestOK:
		return fmt.Sprintf("%s via %d driver(s) (below 1.3)", bestVersion, len(p.ICDs))
	case p.Loader:
		return "loader present, no drivers registered"
	default:
		return "not detected"
	}
}
