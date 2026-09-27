package main

// provisionSentinel is the host→guest key-provisioning wire contract
// (FID-2026-0917-002): the guest's provision-key watcher matches this
// prefix on its Wayland clipboard. Platform-neutral on purpose — the
// cross-platform contract pins in provision_key_test.go must see the same
// truth as the Windows launcher path (provision_key.go).
const provisionSentinel = "SAVANTOS-KEY:"
