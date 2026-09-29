package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestLiveReconstructShippedPayload is an OPT-IN live probe (the T2.1 gate's
// "real behavior" half): it drives the shipped reader against the actual
// published payload in guest-image/out/contract. The seed is a copy of the
// published rootfs.ext4, the previous index is the published caibx itself
// (the honest N->N chain case), and the store is EMPTY — every chunk must be
// resolved from the seed through the reader's ID matching. The reconstructed
// image must pass the unchanged full-image digest gate. Skipped unless
// SAVANT_LIVE_PROBE=1 AND the payload exists, so CI stays hermetic.
func TestLiveReconstructShippedPayload(t *testing.T) {
	if os.Getenv("SAVANT_LIVE_PROBE") == "" {
		t.Skip("opt-in live probe: set SAVANT_LIVE_PROBE=1 with the payload present")
	}
	// Want digest: the published T2.1 baseline rootfs (dual-build gate,
	// 2026-09-28). If the payload is rebuilt, update this constant with the
	// new gate digest — the assertion is the record.
	const wantDigest = "ea574cb3600e615551342f405e8eb99ed46cf8497d00e00704ffecf349d27c9f"

	payload := os.Getenv("SAVANT_PROBE_PAYLOAD")
	if payload == "" {
		payload = "../guest-image/out/contract"
	}
	caibx := filepath.Join(payload, "rootfs.ext4.caibx")
	rootfs := filepath.Join(payload, "rootfs.ext4")
	for _, p := range []string{caibx, rootfs} {
		if _, err := os.Stat(p); err != nil {
			t.Skipf("published payload not present (%s): %v", p, err)
		}
	}

	tmp := t.TempDir()
	seed := filepath.Join(tmp, "seed.ext4")
	t.Logf("copying %s -> %s", rootfs, seed)
	t0 := time.Now()
	if err := copyFile(rootfs, seed); err != nil {
		t.Fatalf("seed copy: %v", err)
	}
	t.Logf("seed copy took %s", time.Since(t0).Round(time.Second))

	idxFile, err := os.Open(caibx)
	if err != nil {
		t.Fatalf("open caibx: %v", err)
	}
	defer idxFile.Close()
	idx, err := parseCaibx(idxFile)
	if err != nil {
		t.Fatalf("parseCaibx: %v", err)
	}
	if len(idx.chunks) == 0 {
		t.Fatal("parsed index has no chunks")
	}
	t.Logf("index: %d chunks", len(idx.chunks))

	// Empty store: any store fetch would be a bug (every chunk is
	// seed-served in the N->N case).
	storeDir := filepath.Join(tmp, "store")
	if err := os.MkdirAll(storeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	store, err := newChunkStore(storeDir)
	if err != nil {
		t.Fatalf("newChunkStore: %v", err)
	}
	dest := filepath.Join(tmp, "reconstructed.ext4")
	t0 = time.Now()
	err = reconstructImage(idx, store, seed, caibx, dest, func(done, total int64) {})
	if err != nil {
		t.Fatalf("reconstructImage: %v", err)
	}
	t.Logf("reconstruct took %s", time.Since(t0).Round(time.Second))

	sum, err := fileSHA256Hex(dest)
	if err != nil {
		t.Fatalf("digest of reconstruction: %v", err)
	}
	if sum != wantDigest {
		t.Fatalf("reconstructed digest mismatch:\n got %s\nwant %s", sum, wantDigest)
	}
	t.Logf("PASS: reconstructed image matches the published digest")
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	if _, err := out.ReadFrom(in); err != nil {
		return err
	}
	return out.Sync()
}

func fileSHA256Hex(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := f.WriteTo(h); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
