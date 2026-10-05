//go:build windows

package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

// Vulkan ICD manifests register here (one value per manifest; the value
// name is the JSON path). The Vulkan loader consults this key and its user
// hive sibling; the probe reads the machine hive only — user-registered
// ICDs are a developer setup, and this probe's consumers are diagnostics,
// not policy.
const vulkanICDKeyPath = `SOFTWARE\Khronos\Vulkan\Drivers`

// regEnumNoMoreItems is ERROR_NO_MORE_ITEMS (winreg.h): RegEnumValueW's
// normal end-of-enumeration answer. stdlib syscall lacks RegEnumValue, so
// the export is called directly per the win32 interop contract.
const regEnumNoMoreItems = 259

var procRegEnumValueW = advapi32.NewProc("RegEnumValueW")
var procIsProcessorFeaturePresent = kernel32.NewProc("IsProcessorFeaturePresent")

// pfAVX2InstructionsAvailable is PF_AVX2_INSTRUCTIONS_AVAILABLE (winnt.h):
// the OS's own answer to "can this machine execute AVX2".
const pfAVX2InstructionsAvailable = 40

// readVulkanManifest reads a driver manifest under a hard size bound. The
// path comes from the registry, so the read is bounded by construction: a
// corrupt or hostile value costs a bounded read, never an unbounded
// allocation. An oversize manifest is an error rather than a partial parse —
// the caller leaves that driver's version unknown instead of reporting a
// version read out of a truncated blob.
func readVulkanManifest(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxVulkanManifestBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxVulkanManifestBytes {
		return nil, fmt.Errorf("vulkan ICD manifest exceeds %d bytes", maxVulkanManifestBytes)
	}
	return data, nil
}

// probeVulkanSupport walks the registered Vulkan driver manifests. A missing
// registry key is the ordinary no-driver case (measured live on a
// loader-only machine, 2026-10-03), not a failure; any other registry error
// lands in Error and describe() reports it as unknown. Fail-open throughout:
// a broken registry must never disturb a launch over a diagnostics fact.
func probeVulkanSupport() vulkanProbe {
	var probe vulkanProbe
	if _, err := os.Stat(filepath.Join(os.Getenv("SystemRoot"), "System32", "vulkan-1.dll")); err == nil {
		probe.Loader = true
	}
	var key syscall.Handle
	path, err := syscall.UTF16PtrFromString(vulkanICDKeyPath)
	if err != nil {
		// Unreachable for this constant (it holds no NUL), but reported
		// rather than discarded: a malformed key path must not present
		// itself as the ordinary no-driver case.
		probe.Error = "registry key path invalid"
		return probe
	}
	if err := syscall.RegOpenKeyEx(syscall.HKEY_LOCAL_MACHINE, path, 0, syscall.KEY_READ, &key); err != nil {
		if !errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			probe.Error = "registry key unreadable"
		}
		return probe
	}
	defer syscall.RegCloseKey(key)
	for index := uint32(0); index < 64; index++ {
		name := make([]uint16, 1024)
		nameLen := uint32(len(name))
		r1, _, _ := procRegEnumValueW.Call(uintptr(key), uintptr(index),
			uintptr(unsafe.Pointer(&name[0])), uintptr(unsafe.Pointer(&nameLen)), 0, 0, 0, 0)
		switch r1 {
		case 0:
			icd := vulkanICD{Manifest: syscall.UTF16ToString(name[:nameLen])}
			if data, err := readVulkanManifest(icd.Manifest); err == nil {
				icd.APIVersion = parseVulkanICDAPIVersion(data)
			}
			probe.ICDs = append(probe.ICDs, icd)
		case regEnumNoMoreItems:
			return probe
		default:
			probe.Error = "registry enumeration failed"
			return probe
		}
	}
	return probe
}

// probeAVX2Support asks the OS whether this machine executes AVX2 (step 3c).
// "unknown" is reserved for a missing export; the API's yes/no answer is
// otherwise reported verbatim (measured True here, 2026-10-03).
func probeAVX2Support() string {
	if err := procIsProcessorFeaturePresent.Find(); err != nil {
		return "unknown (api unavailable)"
	}
	r1, _, _ := procIsProcessorFeaturePresent.Call(pfAVX2InstructionsAvailable)
	if r1 != 0 {
		return "yes"
	}
	return "no"
}
