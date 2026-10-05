package main

import (
	"crypto/sha256"
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

// --- deltaReconstruct integration (T2.1 fallback contract, stage 6) ---
//
// The reader tests above pin the mechanics; these pin the integration
// function the launcher actually calls: the one-trust-root advertisement
// check, the fetch-verify-reconstruct-verify chain, and the rule that every
// failure leaves no scaffolding behind for the zst fallback.

// deltaFixtureServer serves the committed fixture chain under the release
// paths deltaReconstruct fetches: both indices, and the sharded store only
// when withStore is set (its absence is the crippled-store case).
func deltaFixtureServer(t *testing.T, withStore bool) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	serveFixture := func(name string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			http.ServeFile(w, r, fixturePath(t, name))
		}
	}
	mux.HandleFunc("/rootfs.ext4.caibx", serveFixture("v2.caibx"))
	mux.HandleFunc("/rootfs.ext4.prev.caibx", serveFixture("base.caibx"))
	if withStore {
		mux.Handle("/rootfs.castr/", http.StripPrefix("/rootfs.castr/",
			http.FileServer(http.Dir(filepath.Join("testdata", "casync", "store")))))
	}
	return httptest.NewServer(mux)
}

// deltaSums builds the SHA256SUMS map deltaReconstruct authenticates the
// downloaded artifacts against.
func deltaSums(t *testing.T) map[string]string {
	t.Helper()
	sums := map[string]string{}
	for name, path := range map[string]string{
		"rootfs.ext4.caibx":      fixturePath(t, "v2.caibx"),
		"rootfs.ext4.prev.caibx": fixturePath(t, "base.caibx"),
		"rootfs.ext4":            fixturePath(t, "v2.bin"),
	} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(data)
		sums[name] = hex.EncodeToString(sum[:])
	}
	return sums
}

// assertNoDeltaScaffolding pins the cleanup contract: after any delta
// attempt, neither the seed nor the downloaded indices may survive for the
// zst fallback to trip over.
func assertNoDeltaScaffolding(t *testing.T, guestDir string) {
	t.Helper()
	for _, leftover := range []string{"rootfs.ext4.seed", "rootfs.ext4.caibx", "rootfs.ext4.prev.caibx", "rootfs.ext4.dpart"} {
		if _, err := os.Stat(filepath.Join(guestDir, leftover)); !os.IsNotExist(err) {
			t.Fatalf("%s must not survive a delta attempt", leftover)
		}
	}
}

func TestDeltaReconstructEndToEnd(t *testing.T) {
	fixturePath(t, "v2.caibx") // skip the suite when fixtures are absent
	guestDir := t.TempDir()
	cached, err := os.ReadFile(fixturePath(t, "base.bin"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(guestDir, "rootfs.ext4"), cached, 0o644); err != nil {
		t.Fatal(err)
	}
	srv := deltaFixtureServer(t, true)
	defer srv.Close()
	allowMeteredOverride.Store(true) // hermetic: never pause on a metered host
	defer allowMeteredOverride.Store(false)
	cfg := &config{guestDir: guestDir}
	if !deltaReconstruct(srv.Client(), cfg, srv.URL, deltaSums(t), &progressUI{}) {
		t.Fatal("delta path must succeed on the fixture chain")
	}
	assertDigest(t, filepath.Join(guestDir, "rootfs.ext4"), mustReadFixture(t, "v2.bin"))
	assertNoDeltaScaffolding(t, guestDir)
}

// TestDeltaReconstructFallsBackWithoutDeltaArtifacts pins the additive
// contract at the integration seam: a release whose sums carry no delta
// entries returns false BEFORE touching the cached image — no rename, no
// fetch, no cleanup, the zst path takes over byte-for-byte unchanged.
func TestDeltaReconstructFallsBackWithoutDeltaArtifacts(t *testing.T) {
	fixturePath(t, "v2.caibx")
	guestDir := t.TempDir()
	cached, err := os.ReadFile(fixturePath(t, "base.bin"))
	if err != nil {
		t.Fatal(err)
	}
	rootfs := filepath.Join(guestDir, "rootfs.ext4")
	if err := os.WriteFile(rootfs, cached, 0o644); err != nil {
		t.Fatal(err)
	}
	sums := map[string]string{"rootfs.ext4": "0000000000000000000000000000000000000000000000000000000000000000"}
	// The release URL is unroutable on purpose: any fetch would fail the test
	// via the untouched-image assertion below, not silently.
	if deltaReconstruct(&http.Client{}, &config{guestDir: guestDir}, "http://127.0.0.1:1/unreachable", sums, &progressUI{}) {
		t.Fatal("a release without delta entries must fall back")
	}
	got, err := os.ReadFile(rootfs)
	if err != nil || string(got) != string(cached) {
		t.Fatalf("cached image must be untouched when no delta is advertised: %v", err)
	}
}

// TestDeltaReconstructCleansUpWhenIndexUnreachable: the advertisement is
// present but the artifacts are not. The seed rename has already happened by
// then, so the failure path must leave no scaffolding — and the cached image
// must be either gone (the digest-failed image is dropped; the zst path
// re-downloads) or restored intact, never a half-state.
func TestDeltaReconstructCleansUpWhenIndexUnreachable(t *testing.T) {
	fixturePath(t, "v2.caibx")
	guestDir := t.TempDir()
	cached, err := os.ReadFile(fixturePath(t, "base.bin"))
	if err != nil {
		t.Fatal(err)
	}
	rootfs := filepath.Join(guestDir, "rootfs.ext4")
	if err := os.WriteFile(rootfs, cached, 0o644); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.NotFoundHandler())
	defer srv.Close()
	allowMeteredOverride.Store(true)
	defer allowMeteredOverride.Store(false)
	if deltaReconstruct(srv.Client(), &config{guestDir: guestDir}, srv.URL, deltaSums(t), &progressUI{}) {
		t.Fatal("an unreachable index must fall back")
	}
	assertNoDeltaScaffolding(t, guestDir)
	if now, err := os.ReadFile(rootfs); err == nil && string(now) != string(cached) {
		t.Fatal("a half-written cached image must never survive a failed delta attempt")
	}
}

// TestDeltaReconstructCleansUpOnMissingChunks: the indices fetch and verify,
// but the store cannot serve the image's chunks — reconstruction fails and
// the same cleanup contract holds.
func TestDeltaReconstructCleansUpOnMissingChunks(t *testing.T) {
	fixturePath(t, "v2.caibx")
	guestDir := t.TempDir()
	cached, err := os.ReadFile(fixturePath(t, "base.bin"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(guestDir, "rootfs.ext4"), cached, 0o644); err != nil {
		t.Fatal(err)
	}
	srv := deltaFixtureServer(t, false)
	defer srv.Close()
	allowMeteredOverride.Store(true)
	defer allowMeteredOverride.Store(false)
	if deltaReconstruct(srv.Client(), &config{guestDir: guestDir}, srv.URL, deltaSums(t), &progressUI{}) {
		t.Fatal("a store that cannot serve the image must fall back")
	}
	assertNoDeltaScaffolding(t, guestDir)
}

// TestReconstructReplacesStalePartial: a leftover .dpart from an interrupted
// reconstruction must be consumed by the next attempt, never merged into the
// image it produces.
func TestReconstructReplacesStalePartial(t *testing.T) {
	storeDir := filepath.Join("testdata", "casync", "store")
	dest := filepath.Join(t.TempDir(), "recon.bin")
	if err := os.WriteFile(dest+".dpart", []byte("stale partial from an interrupted run"), 0o644); err != nil {
		t.Fatal(err)
	}
	idx := mustParse(t, fixturePath(t, "v2.caibx"))
	st, err := newChunkStore(storeDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := reconstructImage(idx, st, "", "", dest, nil); err != nil {
		t.Fatalf("reconstruct over a stale partial: %v", err)
	}
	assertDigest(t, dest, mustReadFixture(t, "v2.bin"))
}

func mustReadFixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(fixturePath(t, name))
	if err != nil {
		t.Fatal(err)
	}
	return data
}
