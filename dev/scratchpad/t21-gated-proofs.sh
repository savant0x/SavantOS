#!/bin/bash
# Operator-gated live proofs + E2E serving recipe (T2.1 follow-ups).
# NOTHING here runs without explicit per-launch operator approval
# (binding ruling 2026-09-28: real targets only, approval per launch).
#
# 1) T1.2 live proof — headless -fresh reset on the disposable accept target
#    (C:\Users\spenc\savantos-accept, dev-anchor.json present, instant mode).
#    Proves: reset proceeds with no dialog, cancel honored is unit-locked,
#    old disk retained under vm/before-reset-*/, guest comes back.
scripts/dev/dev-vm.sh boot -fresh -headless --data-dir "$USERPROFILE/savantos-accept"

# 2) Polkit rung proof (FID-2026-0928-001 image half): re-provision the same
#    target from the CURRENT published baseline (the one embedding the rule),
#    then exercise the close ladder to the escalation rung on the real guest.
scripts/dev/dev-vm.sh provision --fresh --data-dir "$USERPROFILE/savantos-accept"
scripts/dev/dev-vm.sh boot --data-dir "$USERPROFILE/savantos-accept"
# then: trigger close repeatedly; expect the escalation rung (polkit) to
# close the guest and the rung verdict to be recorded (8dc034f behavior).

# 3) E2E delta proof (no VM needed until the final boot):
#    a) wait for the N+1 build to publish out/contract (pruned store +
#       rootfs.ext4.prev.caibx + delta SHA256SUMS entries)
#    b) serve with Range support (python -m http.server IGNORES Range;
#       the launcher's 200-restart fallback would silently disable resume —
#       use a range-capable server):
docker run --rm -d --name savant-release -p 8399:80 \
  -v "$(cygpath -w "$PWD/guest-image/out/contract"):/usr/local/apache2/htdocs:ro" \
  httpd:2.4
#    c) point a launcher data dir that holds the N-1 payload at it:
#       (the seed = its guest/rootfs.ext4; the reader fetches ONLY the
#       pruned chunks + the two indices)
# build output: app/savantos.exe (or the installed launcher)
./app/savantos.exe -data-dir "$USERPROFILE/savantos-e2e-delta" \
  -release http://127.0.0.1:8399 \
  -sums-sha256 "$(sha256sum guest-image/out/contract/SHA256SUMS | cut -d' ' -f1)"
#    d) measure: the log's delta lines report chunks fetched vs seed-supplied
#       and bytes transferred (target < 100 MB for a realistic pair).
#    e) the final boot of the reconstructed image is operator-gated.
