package main

import (
	"strings"
	"testing"
)

func TestUninstallKeyNameIsStablePerInstall(t *testing.T) {
	def := `C:\Users\me\AppData\Local\SavantOS`
	if got := uninstallKeyName(def, def); got != "SavantOS" {
		t.Fatalf("default install key: %q", got)
	}
	a := uninstallKeyName(`E:\SavantOS\SavantOS`, def)
	b := uninstallKeyName(`e:\savantos\savantos\`, def)
	if a != b || !strings.HasPrefix(a, "SavantOS-") || len(a) != len("SavantOS-")+8 {
		t.Fatalf("alternate install keys differ or are malformed: %q %q", a, b)
	}
	if uninstallKeyName(`D:\Other`, def) == a {
		t.Fatal("different folders must not share a key")
	}
	if got := uninstallDisplayName(`E:\SavantOS\SavantOS`, def); got != `SavantOS (E:\SavantOS\SavantOS)` {
		t.Fatalf("display name: %q", got)
	}
}

func TestUninstallCommandQuotesPaths(t *testing.T) {
	got := uninstallCommand(`E:\My SavantOS\SavantOS.exe`, `E:\My SavantOS`)
	if got != `"E:\My SavantOS\SavantOS.exe" -dir "E:\My SavantOS" -uninstall` {
		t.Fatalf("command: %s", got)
	}
	if displayVersion("v0.0.12-preview") != "0.0.12-preview" {
		t.Fatal("display version keeps the v prefix")
	}
}
