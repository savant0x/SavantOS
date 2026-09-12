#!/bin/bash
# Boot proof for the Phase 1 payload: the UNMODIFIED launcher must download,
# authenticate, unpack, receipt, and boot the new image from a local release
# base on a fresh data directory. This script stages the data dir (runtime
# adopted via the launcher's own archive-identity path), serves the release
# base over loopback HTTP, and prints the exact launcher command to run.
#
# The launcher runs in a separate terminal/window (it owns a UI); this script
# stays alive serving HTTP until interrupted.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
out="$here/out"
contract="$out/contract"

[[ -f $contract/SHA256SUMS ]] || {
    echo "boot-proof: no payload yet — run guest-image/build.sh first" >&2
    exit 1
}
[[ -f $out/release-base.json ]] || {
    echo "boot-proof: no release-base.json — run guest-image/build.sh first" >&2
    exit 1
}

port=${BOOT_PROOF_PORT:-8765}
data_dir=${BOOT_PROOF_DATA:-$USERPROFILE/savantos-phase1}
share_dir=${BOOT_PROOF_SHARE:-$USERPROFILE/savantos-share}
ssh_port=${BOOT_PROOF_SSH:-2223}

sums_digest=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sumsSha256"])' "$out/release-base.json")
# The launcher fetches "$release/SHA256SUMS" then "$release/<artifact>" —
# the release NAME is receipt metadata, not a URL path, so the base is the
# server root serving the contract dir.
base_url="http://127.0.0.1:$port"

launcher="$repo_root/app/SavantOS-dev.exe"
[[ -f $launcher ]] || (cd "$repo_root/app" && go build -o SavantOS-dev.exe .)

w() { cygpath -w "$1"; }

# --- stage the data dir: runtime receipt from the e2e install keeps the real
# alpha10 archive identity, so the launcher adopts the runtime instead of
# downloading it (runtimeArchiveMatches, app/runtime_state.go).
seed="$USERPROFILE/Downloads/savantos-e2e/data"
if [[ -d $seed/runtime && ! -d $data_dir/runtime ]]; then
    echo "[boot-proof] adopting the proven WINQ-EMU runtime from $seed"
    mkdir -p "$data_dir"
    cp -r "$seed/runtime" "$data_dir/runtime"
fi

mkdir -p "$data_dir" "$share_dir"

echo "[boot-proof] serving $contract at $base_url (Ctrl+C to stop)"
echo
echo "  Then, in another terminal:"
echo
echo "  $launcher -dir \"$(w "$data_dir")\" \\"
echo "      -release \"$base_url\" -sums-sha256 \"$sums_digest\" \\"
echo "      -share \"$(w "$share_dir")\" -ssh $ssh_port -instant -no-update"
echo

cd "$contract"
exec python3 -m http.server "$port" --bind 127.0.0.1
