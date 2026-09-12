# Snapshot-date consistency check for the guest-image builder.
# mkosi.conf and snapshot.lock.json must pin the same Arch snapshot;
# build.sh sources this from both.

fail() {
    echo "snapshot-lock: $*" >&2
    exit 1
}

lock_file="${1:?usage: check-snapshot-lock.sh <path-to-snapshot.lock.json> <path-to-mkosi.conf>}"

[[ -f $lock_file ]] || fail "missing $lock_file"
[[ -f $2 ]] || fail "missing $2"

date_from_lock=$(python3 - "$lock_file" <<'PY'
import json
import pathlib
import sys

lock = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(lock["snapshotDate"])
PY
) || fail "snapshot.lock.json is not valid JSON with a snapshotDate"

[[ $date_from_lock =~ ^[0-9]{8}$ ]] || fail "snapshotDate must be YYYYMMDD: $date_from_lock"

mirror_from_lock=$(python3 - "$lock_file" <<'PY'
import json
import pathlib
import sys

lock = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(lock["mirror"])
PY
) || fail "snapshot.lock.json is not valid JSON with a mirror"

# archive.archlinux.org nests the date: repos/YYYY/MM/DD/
nested=$(printf '%s' "$date_from_lock" | sed 's|^\(....\)\(..\)\(..\)$|\1/\2/\3|')
[[ $mirror_from_lock == "https://archive.archlinux.org/repos/$nested/" ]] ||
    fail "mirror $mirror_from_lock does not match snapshotDate $date_from_lock (expected .../repos/$nested/)"

conf_date=$(sed -n 's|.*repos/\([0-9]\{4\}/[0-9]\{2\}/[0-9]\{2\}\)/.*|\1|p' "$2" | head -1)
[[ $conf_date == "$nested" ]] ||
    fail "mkosi.conf pins snapshot ${conf_date:-<none>} but the lock pins $nested"

echo "snapshot-lock: OK (Arch snapshot $date_from_lock)"
