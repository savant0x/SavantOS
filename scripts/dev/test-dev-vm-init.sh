#!/bin/bash
# Verification for the dev-vm.sh --reseed fix (Law 3: evidence from tool output).
# Exercises cmd_init's paths against temp dirs; never touches a real install
# or the default %USERPROFILE%\savantos-dev.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/dev/dev-vm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { echo "  PASS $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; fail=$((fail+1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (=$3)"; else bad "$1 (want $3, got $2)"; fi; }

run_init() { # run_init <devdir> <share> <args...>
  local dd="$1" sh="$2"; shift 2
  SAVANTOS_DEV_DIR="$dd" SAVANTOS_DEV_SHARE="$sh" SAVANTOS_DEV_PORT=2299 \
    bash "$SCRIPT" init "$@" >"$TMP/out" 2>"$TMP/err"
  echo $?
}

echo "== 1. syntax =="
if bash -n "$SCRIPT"; then ok "bash -n"; else bad "bash -n"; fi

echo "== 2. help advertises --reseed =="
if bash "$SCRIPT" help | grep -q -- '--reseed'; then ok "help lists --reseed"; else bad "help lists --reseed"; fi

echo "== 3. first-run seed into a nonexistent dir (baseline still works) =="
SEED="$TMP/seed"; mkdir -p "$SEED/payload"
echo "hello" > "$SEED/payload/marker.txt"
head -c 3000000 /dev/zero > "$SEED/payload/zeros.bin"
printf 'ABC' > "$SEED/payload/small.bin"
rc=$(run_init "$TMP/fresh" "$TMP/fresh-share" --seed-from "$SEED")
check "exit" "$rc" "0"
check "marker copied" "$(cat "$TMP/fresh/payload/marker.txt" 2>/dev/null)" "hello"
check "zeros size" "$(wc -c < "$TMP/fresh/payload/zeros.bin" 2>/dev/null)" "3000000"
check "small size" "$(wc -c < "$TMP/fresh/payload/small.bin" 2>/dev/null)" "3"
check "anchor written" "$(cat "$TMP/fresh/dev-anchor.json" 2>/dev/null)" '{"kind": "savantos-dev-anchor", "version": 1}'

echo "== 4. negative: re-seed without --reseed refuses (exit 2) =="
rc=$(run_init "$TMP/fresh" "$TMP/fresh-share" --seed-from "$SEED")
check "exit" "$rc" "2"
if grep -q 'already has content' "$TMP/err"; then ok "message explains"; else bad "message explains"; fi
if grep -q -- '--reseed' "$TMP/err"; then ok "message names the flag"; else bad "message names the flag"; fi
check "data dir untouched" "$(cat "$TMP/fresh/payload/marker.txt" 2>/dev/null)" "hello"

echo "== 5. negative: --reseed with a bad seed source changes nothing =="
rc=$(run_init "$TMP/fresh" "$TMP/fresh-share" --seed-from "$TMP/nope" --reseed)
check "exit" "$rc" "2"
if grep -q 'not a directory' "$TMP/err"; then ok "seed error first"; else bad "seed error first"; fi
check "still no backup dir" "$(find "$TMP" -maxdepth 1 -name 'fresh.bak-*' | wc -l)" "0"
check "data dir untouched" "$(cat "$TMP/fresh/payload/marker.txt" 2>/dev/null)" "hello"

echo "== 6. positive: --reseed replaces and renames the old dir aside =="
# mutate the live target so we can prove the replacement really happened
echo "STALE" > "$TMP/fresh/payload/marker.txt"
rc=$(run_init "$TMP/fresh" "$TMP/fresh-share" --seed-from "$SEED" --reseed)
check "exit" "$rc" "0"
check "content replaced" "$(cat "$TMP/fresh/payload/marker.txt" 2>/dev/null)" "hello"
check "no stale file" "$(ls "$TMP/fresh/payload/stale-only" 2>/dev/null | wc -l)" "0"
BAK=$(find "$TMP" -maxdepth 1 -type d -name 'fresh.bak-*' | head -1)
if [[ -n "$BAK" ]]; then ok "backup exists: $(basename "$BAK")"; else bad "backup exists"; fi
check "backup holds the old content" "$(cat "$BAK/payload/marker.txt" 2>/dev/null)" "STALE"
check "anchor re-written in new dir" "$(cat "$TMP/fresh/dev-anchor.json" 2>/dev/null)" '{"kind": "savantos-dev-anchor", "version": 1}'
check "backup count still 1" "$(find "$TMP" -maxdepth 1 -type d -name 'fresh.bak-*' | wc -l)" "1"

echo "== 7. idempotence: two reseeds in a row both succeed =="
rc=$(run_init "$TMP/fresh" "$TMP/fresh-share" --seed-from "$SEED" --reseed)
check "second reseed exit" "$rc" "0"
check "two backups now" "$(find "$TMP" -maxdepth 1 -type d -name 'fresh.bak-*' | wc -l)" "2"

echo "== 8. existing but EMPTY dir seeds without --reseed =="
mkdir -p "$TMP/empty"
rc=$(run_init "$TMP/empty" "$TMP/empty-share" --seed-from "$SEED")
check "exit" "$rc" "0"
check "content landed" "$(cat "$TMP/empty/payload/marker.txt" 2>/dev/null)" "hello"

echo "== 9. negative: --reseed refuses while a guest answers on the port =="
# guest_up() shells out to ssh; a stub earlier on PATH that succeeds is an
# honest way to exercise the branch without a live VM.
STUB="$TMP/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\nexit 0\n' > "$STUB/ssh"
chmod +x "$STUB/ssh"
PATH="$STUB:$PATH" SAVANTOS_DEV_DIR="$TMP/fresh" SAVANTOS_DEV_SHARE="$TMP/fresh-share" \
  SAVANTOS_DEV_PORT=2299 bash "$SCRIPT" init --seed-from "$SEED" --reseed \
  >"$TMP/out" 2>"$TMP/err"
check "exit" "$?" "2"
if grep -q 'still answering on port' "$TMP/err"; then ok "live-guest guard fires"; else bad "live-guest guard fires"; fi
check "no third backup created" "$(find "$TMP" -maxdepth 1 -type d -name 'fresh.bak-*' | wc -l)" "2"

echo "== 10. no-seed path still creates the dir + anchor =="
rm -rf "$TMP/noseed"
rc=$(run_init "$TMP/noseed" "$TMP/noseed-share")
check "exit" "$rc" "0"
if [[ -d "$TMP/noseed" ]]; then ok "dir created"; else bad "dir created"; fi
check "anchor written" "$(cat "$TMP/noseed/dev-anchor.json" 2>/dev/null)" '{"kind": "savantos-dev-anchor", "version": 1}'

echo "== 11. unknown option still rejected =="
rc=$(run_init "$TMP/fresh" "$TMP/fresh-share" --bogus)
check "exit" "$rc" "2"

echo
echo "RESULT: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
