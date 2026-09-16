//go:build !windows

package main

// Non-Windows builds (CI's ubuntu gates, tests) have no connectivity hint:
// fail-open to "not metered, platform-unavailable". The policy code above
// this seam is fully exercised on any OS via the override atomics.
func probeMeteredLink() (meteredCost, string) {
	return costUnknown, "nonwindows-default"
}
