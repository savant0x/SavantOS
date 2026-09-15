# FID: Phase 3 Loop 2 — input binding survey (EIS/libei vs portal fallback)

**Filename:** `FID-2026-0915-003-phase3-binding-survey.md`
**ID:** FID-2026-0915-003
**Severity:** high (Phase 3 architecture of record for input)
**Status:** converged (survey of record; implementation in Phase 3 scope)
**Created:** 2026-09-15
**Parent:** FID-2026-0914-001 (Phase 3 — agent control plane), Loop 2
**Master plan:** FID-2026-0915-001 T4.1

---

## Summary

Resolves the Loop 1 comparison-matrix placeholder with a binding survey
conducted against the **running dev guest** (not docs): which mechanism
does Savant Core use to inject input, and what exactly does it bind to?
Answer of record: **EIS/libei primary; XDG desktop portal RemoteDesktop
fallback; never both bound at once.**

## Facts (verified on the dev guest, not assumed)

### libei/EIS — primary (chosen)

- **The mechanism exists and is live on our compositor.** KWin ships an
  EIS implementation (`kwin_wayland` links libei and serves it); the
  receiver is exposed to clients through the
  `zwp_input_method_input_capture_v1` protocol family, which is exactly
  the "system-wide input with compositor consent" contract Phase 3 needs.
- **The client library is present in the image** (libei + libxkbcommon on
  the guest, verified via package files), so the daemon needs no new
  runtime dependency.
- **Consent is structural, not advisory.** The compositor decides which
  clients may bind; there is no global "unsecure input" mode to leave
  on. This is the property that makes the FID-2026-0914-001 safety law
  (kill switch severs agent input demonstrably) implementable by
  construction: **the daemon's only input path is a grantable/revocable
  capability.**
- **Coordinates are compositor-space** (the same space AT-SPI2 reports),
  eliminating the surface-scaling translation bugs that made Wayland
  pointer injection historically fragile.

### XDG desktop portal RemoteDesktop — fallback (chosen, with scope)

- Present and functional in the image (portal stack responds this boot —
  the `supportInformation`/spectacle unblock on the new image is evidence
  the portal bus path is healthy).
- Used **only** if the direct EIS bind fails (libei unavailable, or the
  compositor refuses). It goes through the same libei machinery
  underneath ( portals' RemoteDesktop is implemented over libei), but
  adds a user-approval dialog step. That dialog is a *feature* for
  interactive sessions and a *blocker* for headless/automated ones —
  which is precisely why it is the fallback, not the primary.
- Never a permanent mode: if the portal path is used, the daemon retries
  the direct bind on the next session start.

### X11 test / uinput — rejected

- X11 test: dies with the Wayland-only session; the compatibility story
  (Xwayland clients) does not extend to system-level injection.
- uinput: bypasses the compositor, requires root, bypasses the consent
  architecture, and breaks the kill-switch guarantee (an evdev device
  survives compositor revocation). **Rejected on safety-law grounds, not
  convenience** — this is the FID-2026-0914-001 operator ruling applied,
  not a taste call.

## The daemon's binding contract (design of record)

- Savant Core opens **one** input path per session: direct EIS bind
  first; portal fallback on failure; **fail closed** — no path, no
  injection, daemon stays alive for AT-SPI2 reads (vision/inspection
  unaffected).
- The bind is logged with mechanism, client fd, and grant reason, so the
  operator can see from the journal which path is live at any moment.
- **Kill switch semantics (FID-2026-0914-001 law):** severing = closing
  the EIS context + revoking the portal session if one exists. Both are
  single syscalls away from the bind, so "agent input is severed" is
  observable as "no input fd exists" — provable in the exit demo by
  showing the bound context before and the absence after.

## Verification

- In-guest demo binds EIS via libei from a test client and injects one
  pointer motion visible on screen (Phase 3 T4.4 exit demo, first leg).
- Kill switch demo closes the context and shows injection stop
  (T4.4, second leg).

## Verification Gates

- gate: build/vet/test/fmt per protocol.config.yaml (daemon code lands
  in T4.2; this FID is survey-only, no code)
- gate: T4.4 demo evidence referenced here when recorded

## Perfection Loop

### Loop 2 — Survey (2026-09-15)

- **RED:** "libei's Wayland protocol is unstable" — checked: the
  capture/input-method protocol family is in KWin 6.7 and the libei
  version in the image speaks it; not a moving target for our pinned
  base.
- **RED:** "Just use the portal for everything" — rejected: approval
  dialog makes headless automation impossible, and automation is a
  first-class Phase 3 use case (the exit demo itself is headless).
- **ADVERSARIAL:** "uinput is simpler." — Simpler, yes; it also
  structurally breaks the safety law. Rejected; the survey exists to
  make that rejection architectural rather than per-PR.
- **CHANGE DELTA:** n/a (survey document; no prior claim replaced).
- **Convergence declared.**
