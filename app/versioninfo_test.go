package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"testing"
	"unicode/utf16"
)

func utf16le(s string) []byte {
	out := make([]byte, 0, len(s)*2)
	for _, u := range utf16.Encode([]rune(s)) {
		out = append(out, byte(u), byte(u>>8))
	}
	return out
}

// fixedFileInfo reads the FILEVERSION and PRODUCTVERSION out of the compiled
// resource's VS_FIXEDFILEINFO block, which is what Windows actually reports.
func fixedFileInfo(t *testing.T, syso []byte) (file, product [4]uint16) {
	t.Helper()
	sig := make([]byte, 4)
	binary.LittleEndian.PutUint32(sig, 0xFEEF04BD)
	i := bytes.Index(syso, sig)
	if i < 0 || i+24 > len(syso) {
		t.Fatal("no VS_FIXEDFILEINFO block in rsrc_windows_amd64.syso")
	}
	read := func(off int) [4]uint16 {
		ms := binary.LittleEndian.Uint32(syso[i+off:])
		ls := binary.LittleEndian.Uint32(syso[i+off+4:])
		return [4]uint16{uint16(ms >> 16), uint16(ms), uint16(ls >> 16), uint16(ls)}
	}
	return read(8), read(16)
}

// The version block ships inside a committed resource object, so bumping
// currentVersion without regenerating it would quietly ship stale metadata to
// Explorer, Task Manager and the UAC prompt. Regenerate with:
//
//	go run github.com/josephspurrier/goversioninfo/cmd/goversioninfo@v1.7.0 \
//	  -o rsrc_windows_amd64.syso versioninfo.json
func TestVersionInfoResourceMatchesCurrentVersion(t *testing.T) {
	parts := regexp.MustCompile(`^v(\d+)\.(\d+)\.(\d+)`).FindStringSubmatch(currentVersion)
	if parts == nil {
		t.Fatalf("currentVersion %q is not vMAJOR.MINOR.PATCH", currentVersion)
	}
	var want [4]uint16
	for i := range 3 {
		n, err := strconv.Atoi(parts[i+1])
		if err != nil || n > 0xffff {
			t.Fatalf("version component %q does not fit a resource field", parts[i+1])
		}
		want[i] = uint16(n)
	}

	syso, err := os.ReadFile("rsrc_windows_amd64.syso")
	if err != nil {
		t.Fatal(err)
	}
	// Match the trailing NUL of the resource string: without it a shortened
	// currentVersion would pass as a prefix of a stale one, e.g. "v0.0.7"
	// matching inside a leftover "v0.0.7-preview".
	if n := bytes.Count(syso, utf16le(currentVersion+"\x00")); n < 2 {
		t.Errorf("rsrc_windows_amd64.syso carries %q %d time(s), want it in both FileVersion "+
			"and ProductVersion - regenerate it from versioninfo.json", currentVersion, n)
	}
	file, product := fixedFileInfo(t, syso)
	if file != want {
		t.Errorf("compiled FILEVERSION = %v, want %v", file, want)
	}
	if product != want {
		t.Errorf("compiled PRODUCTVERSION = %v, want %v", product, want)
	}

	// versioninfo.json is the source the committed resource is generated from;
	// it must stay in step with currentVersion and the launcher identity.
	data, err := os.ReadFile("versioninfo.json")
	if err != nil {
		t.Fatal(err)
	}
	var vi struct {
		FixedFileInfo struct {
			FileVersion    struct{ Major, Minor, Patch, Build int }
			ProductVersion struct{ Major, Minor, Patch, Build int }
		} `json:"FixedFileInfo"`
		StringFileInfo struct {
			FileVersion      string
			InternalName     string
			OriginalFilename string
			ProductName      string
			ProductVersion   string
		} `json:"StringFileInfo"`
	}
	if err := json.Unmarshal(data, &vi); err != nil {
		t.Fatalf("versioninfo.json: %v", err)
	}
	if vi.StringFileInfo.FileVersion != currentVersion || vi.StringFileInfo.ProductVersion != currentVersion {
		t.Errorf("versioninfo.json version strings are %q/%q, want %q",
			vi.StringFileInfo.FileVersion, vi.StringFileInfo.ProductVersion, currentVersion)
	}
	if got := fmt.Sprintf("%d.%d.%d.%d",
		vi.FixedFileInfo.FileVersion.Major, vi.FixedFileInfo.FileVersion.Minor,
		vi.FixedFileInfo.FileVersion.Patch, vi.FixedFileInfo.FileVersion.Build); got != fmt.Sprintf("%s.%s.%s.0", parts[1], parts[2], parts[3]) {
		t.Errorf("versioninfo.json FileVersion = %s, want %s.%s.%s.0", got, parts[1], parts[2], parts[3])
	}
	if vi.FixedFileInfo.ProductVersion != vi.FixedFileInfo.FileVersion {
		t.Errorf("versioninfo.json ProductVersion %v differs from FileVersion %v",
			vi.FixedFileInfo.ProductVersion, vi.FixedFileInfo.FileVersion)
	}
	if vi.StringFileInfo.OriginalFilename != stableLauncherName {
		t.Errorf("versioninfo.json OriginalFilename = %q, want stableLauncherName %q",
			vi.StringFileInfo.OriginalFilename, stableLauncherName)
	}
	if vi.StringFileInfo.ProductName != appTitle || vi.StringFileInfo.InternalName != appTitle {
		t.Errorf("versioninfo.json identity = %q/%q, want appTitle %q",
			vi.StringFileInfo.ProductName, vi.StringFileInfo.InternalName, appTitle)
	}
}
