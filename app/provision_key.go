//go:build windows

package main

// Host side of Savant Code key provisioning (FID-2026-0917-002). The guest's
// provision-key watcher (image /usr/local/lib/savantos/provision-key) looks
// for the sentinel on its Wayland clipboard — which the launcher's own
// clipboard bridge (4449) delivers from this Windows clipboard — and writes
// the CLI's own 0600 credentials.json, then acks back over the bridge's push
// port and scrubs both clipboards. The key never lands in the image.

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"time"
)

const provisionSentinel = "SAVANTOS-KEY:"

// provisionKeySend sets the host clipboard to the sentinel and waits for the
// guest's ack (a clipboard item equal to ackText, delivered guest->host over
// the bridge). Runs from "-provision-key <provider>:<key>" against a RUNNING
// launcher: the clipboard writes go through the same bridge state machine as
// any host copy, and the guest watcher is the only reader that matters.
func provisionKeySend(spec string) int {
	spec = strings.TrimSpace(spec)
	parts := strings.SplitN(spec, ":", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		errorBox("Provision key format: -provision-key OPENROUTER:sk-or-...")
		return 2
	}
	sentinel := provisionSentinel + spec
	if !clipboardSetText(sentinel) {
		errorBox("Could not write the Windows clipboard.")
		return 1
	}
	// Wait for the guest watcher's ack, which arrives as a host clipboard
	// update (the bridge delivers guest->host automatically).
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(2 * time.Second)
		if cur, ok := clipboardGetItem(); ok && cur.Kind == clipText && strings.HasPrefix(string(cur.Data), "savantos: key") {
			logf("provision-key: guest acked: %s", string(cur.Data))
			return 0
		}
	}
	errorBox("No ack from the guest within 90s. Is SavantOS running with the current image (provision-key watcher + clipboard bridge)?")
	return 1
}

// lifecycleProvision handles the "provision <spec>" lifecycle line: a second
// launcher invocation forwards the operator's spec to the VM-owning launcher
// (which owns the Windows clipboard through the bridge).
func lifecycleProvision(spec string) int {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", lifecyclePort), 3*time.Second)
	if err != nil {
		errorBox("SavantOS is not running.")
		return 1
	}
	defer c.Close()
	fmt.Fprintf(c, "provision %s\n", spec)
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, _ = bufio.NewReader(c).ReadString('\n')
	return 0
}
