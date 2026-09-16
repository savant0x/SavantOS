//go:build windows

package main

import (
	"encoding/binary"
	"syscall"
	"unsafe"
)

// probeMeteredLink reads Windows' network connectivity hint for this
// process's connection profile. Verified live 2026-09-16 (Go, this repo's
// toolchain): GetNetworkConnectivityHint is exported by Iphlpapi.dll, and
// NL_NETWORK_CONNECTIVITY_HINT is three 32-bit fields at offsets 0/4/8 —
// Level, Changed (bool + padding), Cost. A larger buffer is passed and only
// the verified offsets are read, so struct growth cannot corrupt the read.
//
// Fail-open: any error reports "not metered" so a broken hint can never
// block a normal machine's downloads; the error is visible in the source.
func probeMeteredLink() (meteredCost, string) {
	proc := procGetNetworkConnectivityHint
	if err := proc.Find(); err != nil {
		return costUnknown, "windows-hint-error"
	}
	var buf [16]byte
	r1, _, _ := proc.Call(uintptr(unsafe.Pointer(&buf[0])))
	if r1 != 0 {
		return costUnknown, "windows-hint-error"
	}
	return meteredCost(binary.LittleEndian.Uint32(buf[8:12])), "windows-hint"
}

var procGetNetworkConnectivityHint = syscall.NewLazyDLL("Iphlpapi.dll").NewProc("GetNetworkConnectivityHint")
