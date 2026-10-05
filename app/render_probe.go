package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Rendering modes chosen by the user through settings.json or -render.
const (
	renderAuto = "auto"
	renderGPU  = "gpu"
	renderCPU  = "cpu"
)

// renderProbeFilename remembers how the last launch reached userspace, so a
// forced-GPU startup failure can tell "this machine never ran the GPU path"
// (keep the pending runtime update) from "the update broke a working GPU
// path" (roll it back). See keepUpdatedRuntimeOnCPU.
const renderProbeFilename = "render-probe.json"

type renderProbe struct {
	Schema int `json:"schema"`
	// Result is renderGPU or renderCPU: how the guest last reached userspace.
	Result string `json:"result"`
	// RuntimeID identifies the QEMU runtime the result was observed with.
	RuntimeID string `json:"runtimeID"`
	// DisplayDriver identifies the Windows display drivers at the time.
	DisplayDriver string `json:"displayDriver"`
	// Vulkan and AVX2 are the host capability facts captured at the same
	// moment (FID-2026-0914-002 steps 3b/3c). Additive since their landing:
	// older records simply omit them, so the schema stays 1.
	Vulkan     string    `json:"vulkan,omitempty"`
	AVX2       string    `json:"avx2,omitempty"`
	RecordedAt time.Time `json:"recordedAt"`
}

func loadRenderProbe(dir string) (*renderProbe, error) {
	data, err := os.ReadFile(filepath.Join(dir, renderProbeFilename))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if len(data) > maxSettingsBytes {
		return nil, fmt.Errorf("%s is too large", renderProbeFilename)
	}
	var p renderProbe
	if err := json.Unmarshal(data, &p); err != nil {
		return nil, err
	}
	if p.Schema != 1 || (p.Result != renderGPU && p.Result != renderCPU) {
		return nil, fmt.Errorf("%s is not a supported render probe record", renderProbeFilename)
	}
	return &p, nil
}

func saveRenderProbe(dir string, p renderProbe) error {
	p.Schema = 1
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(dir, renderProbeFilename)
	tmp := path + ".part"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

// startWithGPU decides the launch's rendering path. CPU is the guarded
// default (FID-2026-0917-001): the GPU path can wedge the compositor when
// the first server-decorated window maps - long after a successful boot, so
// no boot-time probe can prove it safe and "auto" must not gamble the
// desktop on it. Only an explicit gpu choice boots GPU, and the caller warns
// loudly on every such launch.
func startWithGPU(mode string) (bool, string) {
	switch mode {
	case renderCPU:
		return false, "CPU rendering chosen in settings"
	case renderGPU:
		return true, "GPU rendering chosen in settings"
	}
	return false, "CPU rendering (guarded default): GPU rendering can freeze the desktop when a window with a titlebar opens (FID-2026-0917-001); choose GPU in Settings or pass -render gpu to force it"
}

// keepUpdatedRuntimeOnCPU decides what a GPU startup failure means while a
// runtime update is still pending. A machine that already reached the desktop
// on CPU rendering with the previous runtime has a graphics stack that never
// ran GPU mode, so the failure says nothing about the new runtime: keep it and
// fall back to CPU. Any other history rolls the runtime back, since a working
// GPU path may have been broken by the update.
func keepUpdatedRuntimeOnCPU(probe *renderProbe) bool {
	return probe != nil && probe.Result == renderCPU
}

func parseRenderMode(value string) (string, error) {
	switch v := strings.ToLower(strings.TrimSpace(value)); v {
	case "", renderAuto:
		return renderAuto, nil
	case renderGPU, renderCPU:
		return v, nil
	}
	return "", fmt.Errorf("render must be auto, gpu, or cpu")
}

// runtimeIdentity names the QEMU runtime for the probe record: the recorded
// executable hash for a bundled runtime, or the executable's size and
// modification time for a user-managed install without a receipt.
func runtimeIdentity(gpuRoot string) string {
	if data, err := os.ReadFile(filepath.Join(gpuRoot, runtimeReceiptFilename)); err == nil && len(data) <= maxInstallReceiptBytes {
		var receipt runtimeReceipt
		if json.Unmarshal(data, &receipt) == nil && validSHA256(receipt.Executable.SHA256) {
			return "sha256:" + receipt.Executable.SHA256
		}
	}
	info, err := os.Stat(filepath.Join(gpuRoot, "bin", "qemu-system-x86_64w.exe"))
	if err != nil {
		return ""
	}
	return fmt.Sprintf("stat:%d:%d", info.Size(), info.ModTime().UnixNano())
}
