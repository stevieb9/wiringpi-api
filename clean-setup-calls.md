# Plan: Remove all traces of setup_phys() and setup_sys()

> **NEXT ACTION:** V1 — delete the `wiringPiSetupSys` / `wiringPiSetupPhys` XS wraps from `API.xs`
> **LAST SESSION:** Plan created. Full-tree sweep done; every trace located across API.xs, API.pm (code + exports + POD), README, test/, and Changes (history). Nothing edited yet.
> **ARCHIVE:** See clean-setup-calls-archive.md for completed V tasks

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

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V1 | **API.xs** — delete both XS wraps: `int wiringPiSetupSys()` (293-294) and `int wiringPiSetupPhys()` (299). Leave `wiringPiSetup()` / `wiringPiSetupGpio()` intact. | `grep -n 'wiringPiSetupSys\|wiringPiSetupPhys' API.xs` | no output | ⏳ |
| V2 | **API.pm subs** — delete `sub setup_sys {…}` and `sub setup_phys {…}` (130-135). Keep `setup` / `setup_gpio`. | `grep -n 'sub setup_sys\|sub setup_phys' lib/WiringPi/API.pm` && `perl -c -Ilib lib/WiringPi/API.pm` | no grep output; `syntax OK` | ⏳ |
| V3 | **API.pm exports** — remove `wiringPiSetupSys` + `wiringPiSetupPhys` from the `@wpi_c_functions` qw() (17-18), and `setup_sys` + `setup_phys` from the `@wpi_perl_functions` qw() (39). Re-flow the qw() rows tidily. `@EXPORT_OK`/`%EXPORT_TAGS` derive from these arrays, so no further export edits needed. | `awk '/qw\(/,/\);/' lib/WiringPi/API.pm \| grep -n 'setup_sys\|setup_phys\|wiringPiSetupSys\|wiringPiSetupPhys'` then `perl -c -Ilib lib/WiringPi/API.pm` | no grep output; `syntax OK` | ⏳ |
| V4 | **API.pm POD** — drop the two tokens from the EXPORT_OK POD list (568) and delete the `=head2 setup_phys()` and `=head2 setup_sys()` blocks (668-684). Confirm the nearby `=head2 setup_gpio()` and the "only one of the C<setup*()> methods" sentence still read correctly with only `setup`/`setup_gpio` left. | `grep -n 'setup_sys\|setup_phys' lib/WiringPi/API.pm` && `podchecker lib/WiringPi/API.pm` | no grep output; POD `OK` | ⏳ |
| V5 | **README** — remove `setup_sys`/`setup_phys` from the wrapper table (45) and delete the `setup_phys()` and `setup_sys()` description blocks (137-153). (README reads like `pod2text` output; if it is ever regenerated from POD, V4 must land first — it has, by ordering.) | `grep -n 'setup_sys\|setup_phys\|wiringPiSetupSys\|wiringPiSetupPhys' README` | no output | ⏳ |
| V6 | **Delete `test/setup_phys.pl`** — entire file is a phys-mode test. Confirm it is not referenced by MANIFEST or any test runner. (No `test/setup_sys.pl` exists.) | `git rm test/setup_phys.pl` && `grep -rn 'setup_phys' MANIFEST t/ test/` | file removed; no remaining references | ⏳ |
| V7 | **Changes** — add a BREAKING bullet at the **bottom** of the `3.1801 UNREL` section, e.g. `- Removed setup_sys()/setup_phys() (and the wiringPiSetupSys/wiringPiSetupPhys wraps); only setup()/setup_gpio() remain (BREAKING)`. Do **NOT** touch the historical entries at lines 201/223 (shipped releases). | `sed -n '/3.1801  UNREL/,/^$/p' Changes` (visual: new bullet last in section; history untouched) | new UNREL bullet present at section bottom; 201/223 unchanged | ⏳ |
| V8 | **Mac static gate** — run the full sweep (see Environment note) plus `perl -c` and POD syntax. Confirms zero traces remain anywhere except Changes history + planning docs. | sweep cmd above; then `perl -c -Ilib lib/WiringPi/API.pm`; then `prove -Ilib t/pod.t` | sweep prints nothing; `syntax OK`; `t/pod.t` passes | ⏳ |
| V9 | **Pi build/run gate (Pi-only)** — on a Pi with wiringPi 3.18, clean-build and run the suite to prove no dangling XS symbol and the module still loads. | `perl Makefile.PL && make && make test` (on Pi) | compiles, links, all tests pass; no `wiringPiSetupSys/Phys` link errors | ⏳ |
| V10 | **Downstream `RPi::WiringPi` (external repo — tracking)** — removal breaks the consumer. In that distro: drop the phys-mode branch in `RPi/WiringPi.pm:51-54` (the `setup_phys()` call at :52) and clean POD mentions of `setup_sys()`/`setup_phys()` in `Core.pm` (~512,518) and `WiringPi.pm` (~898,902). Cannot be edited from this repo. **Now tracked by the `refactor-setup-modes.md` plan in the `rpi-wiringpi` repo** (added 2026-06-02): its V1 drops the phys-mode dispatch branch (`WiringPi.pm` :51-54), V4 cleans the `setup_sys()`/`setup_phys()` POD in `Core.pm` + `WiringPi.pm`; that plan additionally removes the `RPI_MODE_PHYS` branches in `pin_to_gpio`/`pin_map` (V2) and the `export_pin()`/`unexport_pin()` subs (V3). | (in RPi::WiringPi checkout) `grep -rn 'setup_phys\|setup_sys' lib/` | no calls to removed subs; phys init path dropped/redirected; POD cleaned | ⏳ |

## Discovery Tracking

_None yet._

## Backlog

B1: When V8 passes, update `UPGRADE-3.18.md` — mark **V34** done and note its **V7** precondition (the "setup_sys/setup_phys absent" grep) is satisfied. This plan is V34's detailed breakdown; keep the two in sync rather than duplicating work.

## Explicitly NOT doing

- **Rewriting `Changes` history (lines 201, 223)** — those bullets belong to already-shipped releases (`setup_sys()` export behaviour; `wiringPiSetupPhys()` implemented). Editing shipped changelog history is wrong; the removal is recorded as a new UNREL bullet in V7 instead.
- **Scrubbing `setup_sys`/`setup_phys` mentions out of the planning docs** (`UPGRADE-3.18.md`, this file) — those are intentional records of the work, not live API traces. Removing them would destroy the plan.
- **Touching the phys *translation* helpers** (`phys_to_wpi`/`physPinToWpi`, `phys_to_gpio`/`physPinToGpio`) — these convert physical pin numbers and are independent of the removed phys *setup mode*. Their fate is tracked separately (UPGRADE-3.18.md F9/V31), not here.
