package main

import (
	"crypto/sha512"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// Fixtures are casync-generated (pinned snapshot container, casync 2) and
// committed: base.bin = 512 KiB random + 512 KiB zeros; v2.bin = base with
// 64 KiB replaced at 256 KiB. v2.caibx + store/ describe v2.bin;
// base.caibx is the seed's own index (desync's seed argument form).
func fixturePath(t *testing.T, name string) string {
	t.Helper()
	p := filepath.Join("testdata", "casync", name)
	if _, err := os.Stat(p); err != nil {
		t.Skipf("casync fixtures not present: %v", err)
	}
	return p
}

func TestParseCaibxRoundTrip(t *testing.T) {
	f, err := os.Open(fixturePath(t, "v2.caibx"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	idx, err := parseCaibx(f)
	if err != nil {
		t.Fatalf("parseCaibx: %v", err)
	}
	want, err := os.ReadFile(fixturePath(t, "v2.bin"))
	if err != nil {
		t.Fatal(err)
	}
	if n := len(idx.chunks); n == 0 {
		t.Fatal("no chunks parsed")
	}
	last := idx.chunks[len(idx.chunks)-1]
	if got := last.start + last.size; uint64(got) != uint64(len(want)) {
		t.Fatalf("index covers %d bytes, image is %d", got, len(want))
	}
	// Every chunk's digest must verify against the actual image bytes.
	for i, ch := range idx.chunks {
		got := sha512.Sum512_256(want[ch.start : ch.start+ch.size])
		if got != ch.id {
			t.Fatalf("chunk %d digest mismatch against image bytes", i)
		}
	}
}

func TestReconstructFromStoreAndSeed(t *testing.T) {
	storeDir := filepath.Join("testdata", "casync", "store")
	want, err := os.ReadFile(fixturePath(t, "v2.bin"))
	if err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(t.TempDir(), "recon.bin")

	// (a) store only, no seed
	idx := mustParse(t, fixturePath(t, "v2.caibx"))
	st, err := newChunkStore(storeDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := reconstructImage(idx, st, "", "", dest, nil); err != nil {
		t.Fatalf("reconstruct (no seed): %v", err)
	}
	assertDigest(t, dest, want)

	// (b) with the seed: base.bin + base.caibx give the ID->offset map for
	// the previous image's chunks; only chunks absent from base come from
	// the store.
	st2, _ := newChunkStore(storeDir)
	dest2 := filepath.Join(t.TempDir(), "recon-seed.bin")
	if err := reconstructImage(idx, st2, fixturePath(t, "base.bin"), fixturePath(t, "base.caibx"), dest2, nil); err != nil {
		t.Fatalf("reconstruct (seed): %v", err)
	}
	assertDigest(t, dest2, want)

	// (c) HTTP store
	srv := httptest.NewServer(http.FileServer(http.Dir(storeDir)))
	defer srv.Close()
	st3, _ := newChunkStore(srv.URL)
	dest3 := filepath.Join(t.TempDir(), "recon-http.bin")
	if err := reconstructImage(idx, st3, fixturePath(t, "base.bin"), fixturePath(t, "base.caibx"), dest3, nil); err != nil {
		t.Fatalf("reconstruct (http): %v", err)
	}
	assertDigest(t, dest3, want)
}

func TestReconstructFailsOnCorruptSeedOnly(t *testing.T) {
	// A corrupted seed must NOT corrupt the output: mismatched chunks fall
	// through to the store; the result stays digest-exact.
	storeDir := filepath.Join("testdata", "casync", "store")
	idx := mustParse(t, fixturePath(t, "v2.caibx"))
	want, err := os.ReadFile(fixturePath(t, "v2.bin"))
	if err != nil {
		t.Fatal(err)
	}
	corrupt := filepath.Join(t.TempDir(), "corrupt-seed.bin")
	if err := os.WriteFile(corrupt, []byte("garbage"), 0o644); err != nil {
		t.Fatal(err)
	}
	st, err := newChunkStore(storeDir)
	if err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(t.TempDir(), "recon.bin")
	if err := reconstructImage(idx, st, corrupt, "", dest, nil); err != nil {
		t.Fatalf("reconstruct with corrupt seed: %v", err)
	}
	assertDigest(t, dest, want)
}

func TestReconstructMissingChunkFails(t *testing.T) {
	// An empty store: every chunk missing -> error (call site falls back).
	idx := mustParse(t, fixturePath(t, "v2.caibx"))
	st, err := newChunkStore(t.TempDir()) // empty dir store
	if err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(t.TempDir(), "recon.bin")
	if err := reconstructImage(idx, st, "", "", dest, nil); err == nil {
		t.Fatal("expected error with an empty store")
	}
	if _, err := os.Stat(dest + ".dpart"); !os.IsNotExist(err) {
		t.Fatal("partial file must be cleaned on failure")
	}
}

func TestParseCaibxRejectsMalformed(t *testing.T) {
	// Wrong magic.
	bad := make([]byte, 64)
	binary.LittleEndian.PutUint64(bad[0:], 0x30)
	binary.LittleEndian.PutUint64(bad[8:], 0xdeadbeef)
	if _, err := parseCaibx(bytesReader(bad)); err == nil {
		t.Fatal("expected magic rejection")
	}
	// Truncated.
	good, err := os.ReadFile(fixturePath(t, "v2.caibx"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := parseCaibx(bytesReader(good[:20])); err == nil {
		t.Fatal("expected truncation rejection")
	}
}

func mustParse(t *testing.T, path string) caibxIndex {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	idx, err := parseCaibx(f)
	if err != nil {
		t.Fatalf("parseCaibx(%s): %v", path, err)
	}
	return idx
}

func assertDigest(t *testing.T, path string, want []byte) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if hex.EncodeToString(got) != hex.EncodeToString(want) {
		t.Fatalf("reconstructed bytes differ: got %d bytes, want %d", len(got), len(want))
	}
}

func bytesReader(b []byte) *bytesRd { return &bytesRd{b: b} }

type bytesRd struct{ b []byte }

func (r *bytesRd) Read(p []byte) (int, error) {
	if len(r.b) == 0 {
		return 0, fmt.Errorf("EOF")
	}
	n := copy(p, r.b)
	r.b = r.b[n:]
	return n, nil
}
