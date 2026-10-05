#!/bin/bash
# Publish the gate-passed payload by atomic rename swap (FID-2026-1005-001).
#
# The old tail ran `rm -rf out/contract` FIRST and assembled everything
# afterwards, so any failure in between destroyed the published release
# (live incident: 2026-09-29 husked the published N payload). This script
# inverts that: build.sh hands over a payload that is already complete
# (delta store finalized, runtime archive staged, SHA256SUMS emitted with
# delta entries), and all this script does is verify it, park the previous
# payload with a rename (never a deletion), install the new one, re-verify
# in place, and only then remove the park.
#
# States and recovery (printed on failure):
#   before swap   : $out/contract still the OLD payload — nothing lost
#   between mv's  : OLD at $out/contract.prev, NEW at <staged>/contract
#   after install : NEW at $out/contract, OLD parked at $out/contract.prev
#                   until the post-swap verification passes
#
# Environment (test-only; production ignores them when unset):
#   PT_FAIL_AT        abort at a stage boundary: before-park | between-renames
#                     | after-install | after-verify. Abort-only by design:
#                     no value can skip a verification, and unknown values
#                     fail closed.
#   PT_MV_FAIL_FIRST  simulate a busy handle: fail the first N rename calls
#                     (requires PT_MV_STATE — a counter file the test owns).
#   PT_RETRY_DELAY    seconds between park retries (default 10).
#
# Deliberately free of `find` and `head`: this host's Git Bash is missing
# both, and a publish path must not depend on a healthy coreutils install.
set -euo pipefail

fail() {
    echo "[publish] FATAL: $*" >&2
    exit 1
}

log() {
    echo "[publish] $*"
}

out=${1:?usage: publish-tail.sh <out-dir> <build-dir> <release-name> <version>}
build_dir=${2:?usage: publish-tail.sh <out-dir> <build-dir> <release-name> <version>}
release_name=${3:?usage: publish-tail.sh <out-dir> <build-dir> <release-name> <version>}
version=${4:?usage: publish-tail.sh <out-dir> <build-dir> <release-name> <version>}

staged="$build_dir/contract"
pub="$out/contract"
park="$out/contract.prev"

case ${PT_FAIL_AT:-} in
    '' | before-park | between-renames | after-install | after-verify) ;;
    *) fail "unknown PT_FAIL_AT value: $PT_FAIL_AT" ;;
esac

hook() {
    if [[ ${PT_FAIL_AT:-} == "$1" ]]; then
        fail "test hook: aborting at $1"
    fi
}

# Rename with optional simulated-busy failure (test-only). Every failure
# path below assumes rename semantics: all-or-nothing, never a partial
# directory — that is the property the old `rm -rf` lacked.
sim_mv() {
    if [[ -n ${PT_MV_FAIL_FIRST:-} ]]; then
        local state=${PT_MV_STATE:?PT_MV_STATE (counter file) required with PT_MV_FAIL_FIRST}
        local seen=0
        if [[ -f $state ]]; then
            seen=$(<"$state")
        fi
        if ((seen < PT_MV_FAIL_FIRST)); then
            printf '%s\n' "$((seen + 1))" >"$state"
            return 1
        fi
    fi
    command mv "$@"
}

# The payload contract: the seven gated files plus the sums file. The sums
# themselves then cover everything else (runtime archive, delta store,
# indices) via `sha256sum -c`.
verify_payload() {
    local dir=$1 phase=$2 f
    for f in guest-manifest.json build-spec.json vmlinuz-linux \
        initramfs-linux.img rootfs.ext4 rootfs.ext4.zst rootfs.ext4.caibx \
        SHA256SUMS; do
        [[ -f $dir/$f ]] || fail "$phase: required file missing: $f"
    done
    if ! (cd "$dir" && sha256sum --quiet -c SHA256SUMS); then
        fail "$phase: sha256sum -c SHA256SUMS reported a mismatch"
    fi
    log "$phase: verified (7 gated files present, SHA256SUMS clean)"
}

park_previous() {
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if sim_mv "$pub" "$park" 2>/dev/null; then
            return 0
        fi
        echo "[publish] out/contract busy (attempt $attempt/6); retrying in ${PT_RETRY_DELAY:-10}s" >&2
        sleep "${PT_RETRY_DELAY:-10}"
    done
    return 1
}

[[ -d $out ]] || fail "missing out dir: $out"
[[ -d $staged ]] || fail "missing staged payload: $staged"

# GNU mv silently degrades to copy+delete across filesystems, which would
# reintroduce a destructive window; refuse instead.
if [[ $(stat -c %d "$out") != $(stat -c %d "$staged") ]]; then
    fail "out ($out) and staged payload ($staged) are on different filesystems — mv would degrade to a destructive copy"
fi

# A park left over means a previous run died inside the swap window:
# unresolved evidence, never silently discarded.
if [[ -e $park ]]; then
    fail "stale park present: $park — a previous run died inside the swap window. Restore it (mv \"$park\" \"$pub\") or delete it once reviewed, then re-run"
fi

verify_payload "$staged" "staged payload"
hook before-park

if [[ -e $pub ]]; then
    if ! park_previous; then
        fail "could not park out/contract after 6 attempts — the previous payload is STILL PUBLISHED and intact at $pub; the new payload is intact at $staged; re-run once the handle releases"
    fi
    log "previous payload parked at $park"
else
    log "no previous payload — first publish"
fi
hook between-renames

if ! sim_mv "$staged" "$pub"; then
    fail "install rename failed — recover with the parked payload (mv \"$park\" \"$pub\") or finish the install (mv \"$staged\" \"$pub\"); both generations are intact"
fi
hook after-install

verify_payload "$pub" "published payload"
hook after-verify

# Only now — verified in place — may the previous payload go. rm -rf is
# reserved for this point and nowhere earlier in the publish path.
if [[ -e $park ]]; then
    rm -rf -- "$park"
    log "previous payload removed after verification"
fi

# release-base.json points at what is published RIGHT NOW: emit it last,
# after the swap, with the sums digest of the published payload.
sums_digest=$(sha256sum "$pub/SHA256SUMS" | cut -d' ' -f1)
cat >"$out/release-base.json" <<JSON
{
  "releaseName": "$release_name",
  "version": "$version",
  "sumsSha256": "$sums_digest",
  "note": "Serve this directory over loopback HTTP and pass -release <url> -sums-sha256 <sumsSha256> to the unmodified launcher. Includes the v0.0.1 WINQ-EMU runtime archive so the runtime path authenticates."
}
JSON

echo "[build] GATE GREEN — payload in $pub"
echo "[build] SHA256SUMS digest for -sums-sha256: $sums_digest"
