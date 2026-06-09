# Plan: Remove all traces of setup_phys() and setup_sys()

> **NEXT ACTION:** COMPLETE — all V1-V10 done (2026-06-04). This plan's local work is finished; UPGRADE-3.18.md V34 is marked done. Remaining downstream cleanup (POD, export_pin, SYS/PHYS handling) continues under rpi-wiringpi's `refactor-setup-modes.md` (V2-V9); downstream test execution is gated on UPGRADE-3.18.md V33 (install upgraded module).
> **LAST SESSION (2026-06-04):** Executed V1-V10 on `rpi1`. Removed setup_sys/setup_phys + their XS wraps from API.xs/API.pm/POD/README, deleted test/setup_phys.pl, added the BREAKING Changes bullet. `make test` initially failed under bind-now on the F22 `interruptHandler` dangling symbol (Fix 1) — resolved by pulling UPGRADE V23's interruptHandler removal forward; 54 tests then pass. Downstream: dropped the `/^p/` phys dispatch branch on rpi-wiringpi branch `3.18`. Per B1, marked UPGRADE-3.18.md V34 done.
> **ARCHIVE:** See clean-setup-calls-archive.md for completed V tasks (V1-V10 archived)

## Goal & scope

`setup_phys()` / `setup_sys()` (and the XS C-wraps `wiringPiSetupPhys()` / `wiringPiSetupSys()` that back them) are **deprecated and will never be re-added**. Only `setup()` and `setup_gpio()` remain supported. This is a **BREAKING public-API change** (a new major/minor warranting a Changes note), and it **breaks the downstream `RPi::WiringPi` distribution** (a separate repo — see V10; the downstream cleanup is now tracked there by its own `refactor-setup-modes.md` plan).

This plan is the focused execution of **V34** in `UPGRADE-3.18.md`; when V8 here passes, mark that V34 (and its V7 precondition) done there (see B1).

## Environment note

Per project memory, this module **cannot be built or run on the Mac** — `XSLoader::load` needs the compiled `.so`, which only exists on a Pi. Split the verification accordingly:
- **Mac-runnable:** `grep` sweeps, `perl -c -Ilib lib/WiringPi/API.pm` (XS load is runtime, not BEGIN, so `-c` never reaches it), `podchecker` / `t/pod.t` (POD-syntax only).
- **Pi-only:** `perl Makefile.PL && make && make test`, and any test that does `use WiringPi::API` (e.g. `t/00-load.t`, `t/pod-coverage.t`) — these load the XS.

Reusable "no traces remain" sweep (excludes the legitimate mentions in Changes history and the planning docs):

```
grep -rIn 'setup_phys\|setup_sys\|wiringPiSetupSys\|wiringPiSetupPhys' . \
  | grep -v '\.git/' \
  | grep -vE 'Changes|UPGRADE-3\.18\.md|clean-setup-calls'
```

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all three:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of clean-setup-calls-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
  3. **Delete the V# row from this file's Validation Table.**
- V task ❌: update Actual with `❌ YYYY-MM-DD attempt N: reason`. Rerun same V# with attempt N+1. Do NOT create a new V#.
- Update ARCHIVE pointer to reflect what's archived (e.g., `V1-V2` → `V1-V3`)
- Update NEXT ACTION to next ⏳ row; update LAST SESSION
- Never renumber within a series. New items get next free number.
- **Discovery triage during V# work** — when you find something while working a V task, classify before continuing:
  - Blocks the current V task → add `Fix N: problem discovered during V# — [what + fix]` to `## Discovery Tracking`; resolve as part of this V task's work.
  - Real bug but doesn't block this V task → add a new V# row (next free) to the Validation Table with ⏳; do not detour to fix it now.
  - Non-blocking improvement → add new B# to `## Backlog` (one `B#` per line, each separated by a blank line — never run two entries together, or Markdown collapses them into a single mashed paragraph).
  - Decided not to do → add to `## Explicitly NOT doing` with a one-line justification.
- Move resolved fixes to archive's "Archived Fixes" section; keep only unresolved in main Discovery Tracking
- To promote a backlog item to an active task: assign it the next free V# (e.g., B3 becomes V4) and move to the Validation Table. The B# slot is retired and never reused.

## Validation Table

_All V1-V10 complete — see clean-setup-calls-archive.md. This plan is done._

## Discovery Tracking

_Fix 1 resolved — see archive's Archived Fixes (F22 interruptHandler removal pulled forward from UPGRADE-3.18.md V23; `make test` passes)._

## Backlog

B1: When V8 passes, update `UPGRADE-3.18.md` — mark **V34** done and note its **V7** precondition (the "setup_sys/setup_phys absent" grep) is satisfied. This plan is V34's detailed breakdown; keep the two in sync rather than duplicating work.

## Explicitly NOT doing

- **Rewriting `Changes` history (lines 201, 223)** — those bullets belong to already-shipped releases (`setup_sys()` export behaviour; `wiringPiSetupPhys()` implemented). Editing shipped changelog history is wrong; the removal is recorded as a new UNREL bullet in V7 instead.
- **Scrubbing `setup_sys`/`setup_phys` mentions out of the planning docs** (`UPGRADE-3.18.md`, this file) — those are intentional records of the work, not live API traces. Removing them would destroy the plan.
- **Touching the phys *translation* helpers** (`phys_to_wpi`/`physPinToWpi`, `phys_to_gpio`/`physPinToGpio`) — these convert physical pin numbers and are independent of the removed phys *setup mode*. Their fate is tracked separately (UPGRADE-3.18.md F9/V31), not here.
