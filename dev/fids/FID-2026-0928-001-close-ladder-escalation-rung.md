# FID: The close ladder's privileged escalation rung cannot succeed

**Filename:** `FID-2026-0928-001-close-ladder-escalation-rung.md`
**ID:** FID-2026-0928-001
**Severity:** high
**Status:** fixed — F1 implemented 2026-09-28 (factory polkit rule, `yes`,
power-off only, per the ruling); the live escalation proof and the
escalation-exercising acceptance re-run are pending an image rebuild, since
a shipped rule only reaches future images
**Created:** 2026-09-28 10:40
**YAGNI-Compliance:** Verified
**Parent:** FID-2026-0915-002 (the bounded close ladder this refines)

---

## Summary

The close ladder has three rungs: a graceful QMP powerdown, a privileged
guest-side shutdown over the ssh plane, and a forced QEMU stop. The second
rung — the one that exists specifically for the incident this ladder was
built for, a guest that silently drops the ACPI power event — cannot
succeed. It is issued as an unprivileged `systemctl poweroff -i` over a
`BatchMode=yes` ssh session, and the guest's polkit policy requires
interactive authentication for that action. The launcher logs the
failure and falls through to the forced stop, so a dropped power event
costs a QEMU kill instead of a guest shutdown — the exact outcome the
ladder was designed to prevent.

## Environment

- **OS:** Windows 11 host, Arch guest (factory payload `build-2026-09-22`)
- **Language/Runtime:** Go 1.27 launcher; systemd/polkit in the guest
- **Tool Versions:** OpenSSH client (Git Bash), `systemd` guest
- **Commit/State:** HEAD `9da3650` + uncommitted ladder-verdict fix;
  launcher digest `5d1465dd086a3878`; target `C:\Users\spenc\savantos-accept`

## Detailed Description

### Problem

`app/closeguard.go` builds the escalation as:

```go
exec.Command("ssh",
    "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=5", "-p", strconv.Itoa(port),
    "savant@127.0.0.1", "systemctl poweroff -i")
```

It runs as the unprivileged `savant` user. `systemctl poweroff` from a
non-root user is authorized by polkit action
`org.freedesktop.login1.power-off`, not by sudoers. The factory image
installs **no polkit rules** (no `*.rules` file anywhere under
`guest-image/`), so the distribution default applies.

### Evidence

E1 — the command is refused by polkit, verbatim, over the ssh plane the
ladder uses:

```text
$ ssh -p 2222 savant@127.0.0.1 'systemctl poweroff -i'
Call to PowerOff failed: Access denied as the requested operation
requires interactive authentication. However, interactive authentication
has not been enabled by the calling program.
```

"interactive authentication has not been enabled by the calling program"
is polkit reporting that no agent and no tty were available — which is
exactly what `BatchMode=yes` guarantees.

E2 — no polkit rule exists to grant the action. `find guest-image -name
'*.rules'` and `grep -rn polkit guest-image/` return nothing.

E3 — the builder documents the gap in its own words.
`guest-image/finalize.sh:211-212`:

> restart/shutdown plumbing: polkit agent autostarts with the session …
> Nothing to factory-set beyond the wheel policy already granted in
> Phase 1; **logind defaults allow wheel to poweroff/reboot
> interactively.**

"Interactively" is the whole defect. The desktop path works because a
logged-in session has a polkit agent and a human. The launcher's remote
BatchMode ssh has neither.

E4 — the NOPASSWD wheel grant does not rescue it. `finalize.sh:33`
installs `%wheel ALL=(ALL:ALL) NOPASSWD: ALL` and `:30` puts `savant` in
`wheel`, but that authorizes `sudo`, and the ladder never invokes sudo;
`systemctl poweroff` consults polkit regardless of sudoers.

E5 — the failure is invisible to the acceptance that just passed.
All ten close cycles in the 2026-09-28 run resolved on rung 1
(`graceful=10 escalated=0 forced=0`), so the broken rung was never
exercised. The gate measured cycle count, hang-freedom and exit reasons
— all of which a forced stop satisfies.

### Impact

The ladder still terminates, so this is not a hang and not a data-loss
*guarantee*; it is a loss of the graceful outcome in exactly the incident
it was written for. A guest that drops the power event — the
PowerDevil drop that FID-2026-0915-002 was filed for — is now killed
with `p.Kill()` rather than shut down, so in-guest filesystem and
application state take the abrupt path. The design's stated property,
"graceful first, escalated second, forced last", is two-thirds inert.

## Proposed fix (design of record)

Every real fix is a privilege-boundary change and therefore needed
separate operator approval. **Ruling received 2026-09-28: F1, with
`yes` (never asks) and power-off only — no reboot coverage (YAGNI).**

- **F1 — polkit rule in the factory image. — ADOPTED, as ruled.** Install
  `/etc/polkit-1/rules.d/50-savantos-power.rules` granting the `savant`
  user `org.freedesktop.login1.power-off` and `.power-reboot` with
  `auth_admin_keep` (or `yes`). Smallest change, keeps the decision
  inside polkit, and survives a polkit-agent-less session. Cost: a
  standing privilege grant for one user over two actions, which must be
  justified as "the launcher must be able to shut its own guest down".
  Two refinements at implementation: the value is `yes` (the ruling;
  `auth_admin_keep` still asks once and the escalation has no agent to
  answer), and the rule grants the whole **power-off family** — the bare
  action plus `.power-off-multiple-sessions` (the ssh session is a
  second logind session beside the autologin tty1) and
  `.power-off-ignore-inhibit` (`-i` is `--ignore-inhibitors`) — because
  one remote close consults all three and granting only the bare action
  would reproduce the denial in the exact incident scenario. Reboot
  coverage omitted per the ruling.
- **F2 — root-owned helper.** Ship `/usr/local/bin/savantos-poweroff`
  (root-owned, non-writable) that execs the systemctl call, and have the
  escalation invoke that over ssh. No polkit policy change; the grant is
  explicit, greppable and auditable in the builder. Cost: a root
  executable callable by the session user, which is the same effective
  grant as F1 but more visible.
- **F3 — correct the record instead.** Ship nothing; amend
  FID-2026-0915-002 and the ladder's own doc comment to state that rung 2
  is best-effort and that a dropped power event is expected to end in a
  forced stop. Cost: honest, zero privilege change, and leaves the
  original incident's graceful outcome unimproved.

Recommendation: **F1**. It is the least new machinery, it is the
mechanism the guest already consults, and it keeps the privilege decision
in one reviewable file. F2 is the fallback if the operator prefers no
polkit policy in the image at all.

Whichever is chosen, `close_ladder.go`'s doc comment and
FID-2026-0915-002's "privileged shutdown requested" claim must be
rewritten to match reality. — Both amendments landed with the
implementation (2026-09-28).

## Implementation evidence — 2026-09-28

- `guest-image/skeletons/etc/polkit-1/rules.d/50-savantos-power.rules`
  (new): the ruled grant — the three power-off actions above for
  `subject.user == "savant"` returning `polkit.Result.yes`, with the
  mechanism comment inline (sudoers ≠ polkit; why each of the three
  actions is consulted; reboot excluded per the ruling).
- `guest-image/finalize.sh`: the restart/shutdown comment block no
  longer claims "logind defaults allow wheel to poweroff/reboot
  interactively" is sufficient — it now states the sudoers grant does
  not authorize the action and names the rule that does.
- `app/close_ladder.go` + `app/closeguard.go`: doc comments now state
  the escalation is authorized by the factory polkit rule.
- FID-2026-0915-002: annotated to record that rung 2 was polkit-denied
  until this rule.
- Not yet satisfied, and why: the live escalation proof and the
  acceptance re-run below need a re-provisioned disposable target. The
  image half is now DONE — the T1.3 dual-build (2026-09-28, determinism
  gate green, `rootfs.ext4 a2dbea53…895d5`) produced a baseline payload
  in `guest-image/out/contract` that embeds this rule; the accept target
  still runs the old payload until it is re-provisioned from that
  baseline under an approved boot.

## Verification

- The escalation command, issued exactly as `closeguard.go` builds it,
  powers the guest down and the launcher logs
  `close ladder: privileged shutdown requested (systemctl poweroff -i)`.
- A negative case: with the guest healthy and the powerdown honoured,
  the escalation is not reached at all.
- The 10-cycle close acceptance re-run after the change, with an added
  expectation that the rung is reachable rather than dead.

## Verification Gates

- gate: build/vet/test/fmt per `protocol.config.yaml`
- gate: a guest-side capture showing the escalation succeeding, or the
  polkit denial persisting (a negative result must also be recorded)

## Perfection Loop

### Loop 1 — RED (2026-09-28)

- **RED:** the escalation is issued unprivileged over a non-interactive
  ssh session, against a guest with no polkit grant for the action.
  Catalogued as E1 (the denial, verbatim), E2 (no rule exists), E3 (the
  builder says the policy is interactive-only), E4 (sudoers does not
  apply because the call is polkit-mediated), E5 (the passing acceptance
  never exercised the rung).
- Call-graph reachability: `sshPoweroffEscalation` is constructed by
  `runCloseGuard` and passed as `escalate` into `runCloseLadder`, which
  calls it exactly once. It is wired; it is the *command* that is wrong,
  not the plumbing. This distinguishes the defect from a dead-code bug.
- Convergence declared: analyzed. Implementation required an operator
  ruling because every candidate is a privilege-boundary change, which
  the level-3 authorization in `SCOPE.md` explicitly excludes.

### The ruling (2026-09-28)

1. F1, F2, or F3? — **F1, the polkit rule.**
2. `yes` or `auth_admin_keep`? — **`yes`.** The launcher has no way to
   answer a prompt, so `auth_admin_keep`'s one-time ask is unusable.
3. Reboot coverage? — **Power-off only.** The launcher never reboots
   the guest by this path (the guest announces reboot intent on the
   lifecycle port instead); YAGNI.

### Loop 2 — GREEN in the builder (2026-09-28)

- Rule implemented exactly as ruled (plus the action-family refinement
  recorded in the implementation evidence), builder comment corrected,
  launcher doc comments aligned, FID-2026-0915-002 annotated.
- Outstanding before convergence: the live guest proof (escalation
  rung succeeds end to end) — blocked on an image rebuild and a
  re-provisioned target; the shipped rule only reaches future images.

## Lessons Learned

- A gate that measures "did it terminate" cannot distinguish a graceful
  close from a forced stop. The rung classification added on 2026-09-28
  is what made this defect visible at all: without a recorded rung there
  would have been no way to tell rung 1 from rung 3 in the log.
- Polkit and sudoers are different authorities. "The user has NOPASSWD
  ALL" says nothing about whether a `systemctl` action is authorized.
