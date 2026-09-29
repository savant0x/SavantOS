package main

// Read-only reconstruction of rootfs.ext4 from a casync block index
// (.caibx) plus its chunk store — the T2.1 delta path (FID-2026-0914-002).
//
// Format facts are pinned from desync v1.1.4's source (format.go, const.go,
// chunk.go: CaFormatIndex/Table/tail-marker constants, SHA-512/256 chunk
// digests, raw zstd chunk frames) and cross-checked against committed
// casync-generated fixtures (testdata/casync). Chunk integrity is verified
// per-chunk by digest (casync's own model), so the store needs no separate
// authentication; the index file is the SHA256SUMS-authenticated artifact.
// The reconstructed image is STILL accepted only through the existing
// full-image verifyFileSHA256 at the call site — this reader is an
// optimization, never a second trust root.

import (
	"crypto/sha512"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/klauspost/compress/zstd"
)

// Format constants (desync v1.1.4 const.go).
const (
	caFormatIndex           = 0x96824d9c7b129ff9
	caFormatTable           = 0xe75b9e112f17417d
	caFormatTableTailMarker = 0x4b4f050e5549ecd1
	caFormatSHA512256       = 0x2000000000000000
)

// caibxIndex is the parsed block index: the ordered chunk table of the
// original image.
type caibxIndex struct {
	featureFlags uint64
	chunks       []caibxChunk // in stream order; Start/Size are image offsets
}

type caibxChunk struct {
	id    [32]byte // SHA-512/256 of the uncompressed chunk data
	start uint64
	size  uint64
}

// parseCaibx reads the two format elements (Index, Table) from r. The
// table's items arrive as (offset, chunkID) pairs terminated by offset 0
// plus the four-u64 tail; the last item's Offset is the image size.
func parseCaibx(r io.Reader) (caibxIndex, error) {
	var idx caibxIndex
	readU64 := func() (uint64, error) {
		var b [8]byte
		if _, err := io.ReadFull(r, b[:]); err != nil {
			return 0, err
		}
		return binary.LittleEndian.Uint64(b[:]), nil
	}
	expect := func(want uint64, what string) error {
		got, err := readU64()
		if err != nil {
			return err
		}
		if got != want {
			return fmt.Errorf("casync: %s is %x, want %x", what, got, want)
		}
		return nil
	}

	// Element 1: size(=0x30), CaFormatIndex, featureFlags, min/avg/max.
	size, err := readU64()
	if err != nil {
		return idx, err
	}
	if size != 0x30 {
		return idx, fmt.Errorf("casync: index header size %x, want 0x30", size)
	}
	if err := expect(caFormatIndex, "index magic"); err != nil {
		return idx, err
	}
	if idx.featureFlags, err = readU64(); err != nil {
		return idx, err
	}
	for i := 0; i < 3; i++ { // chunk min/avg/max — parsed, not enforced
		if _, err := readU64(); err != nil {
			return idx, err
		}
	}

	// Element 2: size MAX_UINT64, then CaFormatTable, then items until a
	// zero offset, then the four-u64 tail ending in the tail marker.
	// (Element order is [size][magic] throughout — desync's ReadHeader.)
	tsize, err := readU64()
	if err != nil {
		return idx, err
	}
	if tsize != ^uint64(0) {
		return idx, fmt.Errorf("casync: table size %x, want MAX_UINT64", tsize)
	}
	if err := expect(caFormatTable, "table magic"); err != nil {
		return idx, err
	}
	for {
		off, err := readU64()
		if err != nil {
			return idx, err
		}
		if off == 0 {
			break // zero-terminated item list
		}
		var ch caibxChunk
		ch.start = off
		if _, err := io.ReadFull(r, ch.id[:]); err != nil {
			return idx, err
		}
		idx.chunks = append(idx.chunks, ch)
	}
	var x uint64
	if x, err = readU64(); err != nil || x != 0 {
		return idx, fmt.Errorf("casync: table tail zero-fill missing")
	}
	if _, err = readU64(); err != nil { // index offset
		return idx, err
	}
	if _, err = readU64(); err != nil { // size
		return idx, err
	}
	if err := expect(caFormatTableTailMarker, "table tail marker"); err != nil {
		return idx, err
	}
	if idx.featureFlags&caFormatSHA512256 == 0 {
		return idx, fmt.Errorf("casync: index does not use SHA-512/256 digests (flags %x)", idx.featureFlags)
	}
	if n := len(idx.chunks); n > 1 {
		// Item Start values are the offset of the chunk's END within the
		// image (casync convention); compute true start offsets and sizes.
		prev := uint64(0)
		for i := range idx.chunks {
			idx.chunks[i].size = idx.chunks[i].start - prev
			idx.chunks[i].start = prev
			prev += idx.chunks[i].size
		}
	}
	return idx, nil
}

// chunkStore resolves chunk IDs to readers. Local paths serve the sharded
// directory layout (<4-hex>/<64-hex>); http(s) base URLs serve the same
// layout (a static file server over the store directory).
type chunkStore struct {
	base    string // dir path or http(s) base URL
	client  *http.Client
	zstdDec *zstd.Decoder
}

func newChunkStore(base string) (*chunkStore, error) {
	s := &chunkStore{base: base}
	if strings.HasPrefix(base, "http://") || strings.HasPrefix(base, "https://") {
		s.base = strings.TrimRight(base, "/")
		s.client = &http.Client{}
	}
	dec, err := zstd.NewReader(nil)
	if err != nil {
		return nil, err
	}
	s.zstdDec = dec
	return s, nil
}

// fetch returns the UNCOMPRESSED chunk data for id, verifying the
// SHA-512/256 digest of that data against the ID (casync's per-chunk
// integrity model — a corrupted store or seed can never yield silently
// wrong bytes).
func (s *chunkStore) fetch(id [32]byte) ([]byte, error) {
	// Store layout: <first-4-hex-of-ID>/<full-ID-hex>.cacnk — the file name IS
	// the chunk ID (desync's local-store sharding), not a re-hash.
	name := hex.EncodeToString(id[:])
	path := s.base + "/" + name[:4] + "/" + name + ".cacnk"
	var raw []byte
	if s.client != nil {
		resp, err := s.client.Get(path)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusNotFound {
			return nil, errChunkMissing
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("casync: store fetch %s: HTTP %d", name, resp.StatusCode)
		}
		raw, err = io.ReadAll(resp.Body)
		if err != nil {
			return nil, err
		}
	} else {
		var err error
		raw, err = os.ReadFile(filepath.Join(s.base, name[:4], name+".cacnk"))
		if err != nil {
			if os.IsNotExist(err) {
				return nil, errChunkMissing
			}
			return nil, err
		}
	}
	data, err := s.zstdDec.DecodeAll(raw, nil)
	if err != nil {
		// Some stores keep chunks uncompressed; accept that too.
		data = raw
	}
	got := [32]byte(sha512.Sum512_256(data))
	if got != id {
		return nil, fmt.Errorf("casync: chunk %s digest mismatch", name)
	}
	return data, nil
}

var errChunkMissing = fmt.Errorf("casync: chunk missing from store")

// deltaReconstruct attempts the T2.1 casync delta path for an install whose
// rootfs failed its digest check (FID-2026-0914-002). Returns true when the
// new rootfs was reconstructed AND accepted by the unchanged full-image
// digest gate, so the caller skips the zst download; false means "fall
// through to the normal path" for every condition whatsoever — the delta is
// an optimization, never a requirement.
//
// Trust model (one root): the two block indices must be authenticated
// release artifacts — their presence in SHA256SUMS IS the advertisement, so
// nothing is probed and nothing unauthenticated is parsed. Store chunks are
// fetched unauthenticated and verified per-chunk by their SHA-512/256 IDs
// inside the reader; the seed (the previous rootfs, renamed aside, never
// removed up front) is likewise untrusted and digest-checked per chunk. Any
// failure cleans up the seed and partials and reports honestly.
func deltaReconstruct(client *http.Client, cfg *config, release string, sums map[string]string, ui *progressUI) bool {
	guestDir := cfg.guestDir
	rootfs := filepath.Join(guestDir, "rootfs.ext4")
	seed := rootfs + ".seed"
	caibxPath := filepath.Join(guestDir, "rootfs.ext4.caibx")
	prevPath := filepath.Join(guestDir, "rootfs.ext4.prev.caibx")

	cleanup := func() {
		os.Remove(seed)
		os.Remove(caibxPath)
		os.Remove(prevPath)
	}
	fail := func(format string, a ...any) bool {
		logf("delta: not usable: "+format, a...)
		cleanup()
		return false
	}

	wantIdx, okIdx := sums["rootfs.ext4.caibx"]
	wantPrev, okPrev := sums["rootfs.ext4.prev.caibx"]
	if !okIdx || !okPrev || wantIdx == "" || wantPrev == "" {
		return false // release carries no delta artifacts: silent fallback
	}
	if err := os.Rename(rootfs, seed); err != nil {
		return fail("keeping the current image as a seed failed: %v", err)
	}
	ui.setStatus("Updating SavantOS from the existing image (delta)...")
	// Platform-neutral fetch helpers only: this file has no build tag and
	// must compile on the Linux CI target (ensureVerifiedDownload is
	// windows-only; this is the same semantics composed from neutral parts).
	fetchVerified := func(name, dest, wantSum, status string) error {
		if _, err := os.Lstat(dest); err == nil {
			if ok, err := verifyFileSHA256(dest, wantSum, ui.setProgress); err == nil && ok {
				return nil
			}
			_ = os.Remove(dest)
		}
		if err := waitMeteredGate(); err != nil {
			return err
		}
		ui.setStatus("%s", status)
		return downloadVerified(client, normalizedRelease(release)+"/"+name, dest, wantSum, func(next string, done, total int64) {
			ui.setProgress(done, total)
		})
	}
	if err := fetchVerified("rootfs.ext4.caibx", caibxPath, wantIdx, "Fetching update index..."); err != nil {
		return fail("delta index: %v", err)
	}
	if err := fetchVerified("rootfs.ext4.prev.caibx", prevPath, wantPrev, "Fetching update index (previous)..."); err != nil {
		return fail("delta previous index: %v", err)
	}
	store, err := newChunkStore(normalizedRelease(release) + "/rootfs.castr")
	if err != nil {
		return fail("chunk store: %v", err)
	}
	idxF, err := os.Open(caibxPath)
	if err != nil {
		return fail("delta index: %v", err)
	}
	idx, err := parseCaibx(idxF)
	idxF.Close()
	if err != nil {
		return fail("delta index parse: %v", err)
	}
	var total int64
	for i := range idx.chunks {
		total += int64(idx.chunks[i].size)
	}
	if err := requireDiskSpace(guestDir, total+diskSpaceReserve); err != nil {
		return fail("delta preflight: %v", err)
	}
	reconErr := reconstructImage(idx, store, seed, prevPath, rootfs, func(done, tot int64) {
		ui.setProgress(done, tot)
	})
	if reconErr != nil {
		// A failure here leaves rootfs absent or partial; remove it so the
		// zst fallback starts clean (it re-creates from the downloaded zst).
		os.Remove(rootfs)
		return fail("reconstruction: %v", reconErr)
	}
	// The unchanged acceptance gate: the full image digest from SHA256SUMS.
	ok, err := verifyFileSHA256(rootfs, sums["rootfs.ext4"], ui.setProgress)
	if err != nil {
		return fail("verifying the reconstructed image: %v", err)
	}
	if !ok {
		os.Remove(rootfs)
		return fail("the reconstructed image failed its digest check")
	}
	cleanup() // seed consumed; indices are transient scaffolding
	logf("delta: reconstructed the image from the chunk store and the previous image (%d chunks, %.1f MiB transfer ceiling)", len(idx.chunks), float64(total)/(1024*1024))
	return true
}

// reconstructImage rebuilds the image described by idx into dest. Chunks
// are sourced from the store; a chunk whose ID exists in the seed index
// (the PREVIOUS release's caibx, shipped as rootfs.ext4.prev.caibx) is
// instead read from the seed file at its recorded offset and digest-checked
// — the delta win. The seed index is what makes the seed usable: target
// chunk boundaries do not generally align with the seed's own chunking, so
// offset-guessing is not sound; ID lookup is. Both seed and store chunks
// are digest-verified before use, so the seed is untrusted input that can
// only cost fetches, never correctness.
func reconstructImage(idx caibxIndex, store *chunkStore, seedPath, seedIndexPath, dest string, progress func(done, total int64)) error {
	var seed *os.File
	seedOffsets := map[[32]byte]uint64{}
	if seedPath != "" && seedIndexPath != "" {
		sf, err := os.Open(seedPath)
		if err != nil {
			return err
		}
		defer sf.Close()
		seed = sf
		idxF, err := os.Open(seedIndexPath)
		if err != nil {
			return err
		}
		sidx, err := parseCaibx(idxF)
		idxF.Close()
		if err != nil {
			return err
		}
		for i := range sidx.chunks {
			ch := &sidx.chunks[i]
			if _, dup := seedOffsets[ch.id]; !dup {
				seedOffsets[ch.id] = ch.start
			}
		}
	}
	tmp := dest + ".dpart"
	if err := os.Remove(tmp); err != nil && !os.IsNotExist(err) {
		return err
	}
	out, err := os.Create(tmp)
	if err != nil {
		return err
	}
	writeOK := false
	defer func() {
		if !writeOK {
			out.Close()
			os.Remove(tmp)
		}
	}()
	_ = setSparse(out) // sparseness is an optimization; correctness never depends on it
	var total int64
	for i := range idx.chunks {
		ch := &idx.chunks[i]
		var served bool
		if seed != nil {
			if off, ok := seedOffsets[ch.id]; ok {
				buf := make([]byte, ch.size)
				if _, err := seed.ReadAt(buf, int64(off)); err == nil {
					got := [32]byte(sha512.Sum512_256(buf))
					if got == ch.id {
						if _, err := out.WriteAt(buf, int64(ch.start)); err != nil {
							return err
						}
						served = true
					}
				}
			}
		}
		if !served {
			data, err := store.fetch(ch.id)
			if err != nil {
				return err
			}
			if uint64(len(data)) != ch.size {
				return fmt.Errorf("casync: chunk %d length %d, index says %d", i, len(data), ch.size)
			}
			if _, err := out.WriteAt(data, int64(ch.start)); err != nil {
				return err
			}
		}
		total += int64(ch.size)
		if progress != nil {
			progress(total, int64(idx.chunks[len(idx.chunks)-1].start))
		}
	}
	if err := out.Sync(); err != nil {
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmp, dest); err != nil {
		return err
	}
	writeOK = true
	return nil
}
