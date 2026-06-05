# Plan: Make WiringPi::API safe under Perl ithreads (concurrency contract)

> **⛔ PARKED — back burner (2026-06-03).** All wiringPi-threads work is deprioritized behind the ISR migration (`isr-migration.md` / `docs/interrupt-examples.md`). Don't start these tasks until the ISR work lands and the hold is lifted. Usage examples are in `docs/threads-examples.md` (also parked).
> **NEXT ACTION (when resumed):** V2 — `pi_lock`/`pi_unlock` wrappers. (V1 was completed early on 2026-06-04 during `isr-migration.md` V4 — the dead `initThread`/`thread_callback_sv`/`PI_THREAD` shared the interrupt dispatcher's `mine` global, so they were removed together; see that plan's archive.)
> **LAST SESSION:** **Recast 2026-06-03** after the thread-safety audit (see `isr-migration.md`). Original aim — patch wiringPi's `piThreadCreate` for `userdata` and run Perl callbacks in C-spawned threads — is the *wrong tool*: C threads share the one interpreter and can't run concurrent Perl safely. The right model for "main does work while a thread does its own" is **Perl ithreads** (separate interpreter per thread). So this plan now makes WiringPi::API *safe to call from ithreads* and documents the contract; the `piThreadCreate2` patch is demoted to Backlog (only useful for C-only workers).
> **ARCHIVE:** See threads-patch-archive.md for completed V tasks

## Goal

Let users run WiringPi::API concurrently the supported Perl way — `threads`
(ithreads), one interpreter per thread — with the main program free to do other
work. Deliver: (1) remove the dead C-thread code, (2) provide `pi_lock`/`pi_unlock`
for user-side serialization, (3) **document the concurrency contract** the audit
established, and (4) verify it on hardware.

## Why not "patch wiringPi to run Perl in a thread"

The audit (full version in `isr-migration.md`) settles it:

- A Perl callback in a raw pthread shares the **one** parent interpreter;
  `PERL_SET_CONTEXT` only *locates* it, it does not make concurrent execution
  safe. Adding `userdata` to `piThreadCreate` would lift the single-callback
  limit but **not** the concurrency hazard.
- True concurrent Perl needs **separate interpreters** = Perl ithreads. That is a
  core-module capability, not something to reinvent in XS.
- So our job is not to *provide* threads; it is to be **safe to call from** them,
  and to tell users the rules. C-spawned threads remain useful only for C-only
  work (e.g. softPwm/softTone), which wiringPi already ships.

## The concurrency contract (from the audit)

libwiringPi has exactly one mutex (`pinMutex`), used only around ISR
registration. Therefore:

- **Do once, in the main thread, before spawning:** `setup()`, all `pin_mode`,
  pull-up/down + PWM config, and every device `*Setup` (i2c/spi/adc) — these
  mutate process-global state or do read-modify-write on shared registers / the
  unguarded `wiringPiNodes` list.
- **Safe to do concurrently from ithreads afterward:** `digital_write` (write-only
  SET/CLR registers) and `digital_read` (pure read), ideally with each thread
  owning **distinct pins**.
- **Serialize anything else** (post-spawn config changes, shared data) with
  `pi_lock`/`pi_unlock` or `threads::shared` + `lock`.
- **Interrupts:** arm + dispatch within a single thread (see `isr-migration.md`'s
  self-pipe model — a dedicated interrupt ithread is the background pattern).

## Concurrency example (the contract in action)

```perl
use threads; use threads::shared;
use Time::HiRes qw(sleep);
use WiringPi::API qw(setup pin_mode digital_write digital_read pi_lock pi_unlock);

setup();                              # ONCE, in main, before spawning
pin_mode($_, 1) for (0, 2);           # all config up front, single-threaded
pin_mode(3, 0);

my $latest :shared = 0;

# worker A — drives its OWN pin; distinct pin, so the write needs no lock
threads->create(sub {
    while (1) { digital_write(0, 1); sleep 0.5; digital_write(0, 0); sleep 0.5 }
})->detach;

# worker B — samples a sensor, publishes shared state under a lock
threads->create(sub {
    while (1) { my $v = digital_read(3); pi_lock(0); $latest = $v; pi_unlock(0); sleep 0.1 }
})->detach;

# main thread — free to do other Perl work, concurrently
while (1) { pi_lock(0); print "latest: $latest\n"; pi_unlock(0); sleep 1 }
```

Each thread has its own interpreter (safe concurrent Perl); `setup`/`pin_mode`
ran once in main (contract); distinct-pin `digital_write`/`digital_read` are
lock-free; shared state crosses via `:shared` + `pi_lock`.

## Validation environment

**Pi-only** for build/run; off-Pi is parse/syntax only.

- **Quick checks** (off-Pi): XS `process_file` parse; `perl -c -Ilib lib/WiringPi/API.pm`; `podchecker lib/WiringPi/API.pm`.
- **Full gate** (Pi): `perl Makefile.PL && make && make test`, plus an ithread stress exerciser under `valgrind --leak-check=full` / `--tool=helgrind`.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all three:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of threads-patch-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
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
| V1 | **Remove dead C-thread code (F20).** Delete `initThread`, the file-global `thread_callback_sv`, and the GCC-nested `PI_THREAD(myThread)`. | XS parse + `perl -c` + grep gone | parses; no thread-global residue | ✅ 2026-06-04: **done early during `isr-migration.md` V4** (shared the interrupt dispatcher's `mine` global, so removed together; grep-confirmed gone, clean build + `make test` PASS). Row kept for visibility — plan parked. |
| V2 | **`pi_lock`/`pi_unlock` wrappers.** Surface wiringPi's `piLock(int)`/`piUnlock(int)` (XS subs already exist at API.xs:460-465; no Perl layer) as snake_case `pi_lock($key)`/`pi_unlock($key)` with `0..3` key validation; add exports + tags. These give users a simple cross-thread mutex for the contract's "serialize shared/config" rule. | `perl -c -Ilib lib/WiringPi/API.pm` + XS parse | OK; `pi_lock`/`pi_unlock` exported; bad key croaks | ⏳ |
| V3 | **Document the ithread concurrency contract (POD).** Add a "Concurrency / threads" section: the *setup-once-in-main* rule, *distinct-pins* steady-state, *serialize-with-pi_lock*, and the interrupt-thread pattern — with a worked `use threads` example (main busy; a worker on distinct pins; an interrupt ithread). State that this is the supported route for concurrent Perl, and that the module itself requires neither `threads` nor a threaded Perl. | `podchecker lib/WiringPi/API.pm` + `perl -c` | POD clean; contract + example present | ⏳ |
| V4 | **Verify on hardware (Pi).** ithread stress exerciser: `setup()` + all `pin_mode` in main, then spawn N ithreads each toggling/reading **distinct** pins, plus a shared `:shared` counter guarded by `pi_lock`, plus one interrupt ithread (from `isr-migration.md`). Run under `valgrind --leak-check=full` and `--tool=helgrind`. Confirm no crash/corruption and that the documented contract holds; optionally a negative check that concurrent `pin_mode` on a shared GPFSEL bank is racy (justifies the "config in main" rule). Update Changes. | `perl Makefile.PL && make && make test` + ithread exerciser under valgrind/helgrind (Pi) | green; no leak/race within the contract; Changes updated | ⏳ |

## Discovery Tracking

_None yet._

## Backlog

B1: **Upstream `piThreadCreate2(fn, userdata)`** — add `userdata` to wiringPi's `piThread.c` (mirror of ISR2) so C-spawned threads can carry per-thread data. Only useful for **C-only** background workers (no Perl callback), since Perl-in-a-shared-interpreter is unsafe regardless. Lower priority than ithread support; would also impose a patched-libwiringPi dependency. Submit upstream if pursued.

B2: Optional `thread_create` for **C-only** workers riding B1 — e.g. a built-in poll/blink loop implemented in C. Re-evaluate only if a concrete need appears; softPwm/softTone already cover the common cases.

B3: A higher-level Perl helper that encapsulates the "interrupt ithread" boilerplate (spawn + arm + `wait_interrupts` loop), so users get background interrupts without writing the `threads` plumbing.

## Explicitly NOT doing

- **Running Perl callbacks in C-spawned (`piThreadCreate`) threads** — shares the one interpreter; unsafe for concurrent Perl. Use ithreads.
- **Reinventing ithreads in XS** (per-thread `perl_clone`, cross-interpreter SV marshalling) — duplicates core Perl badly.
- **Requiring `threads` / a threaded Perl in the dist** — concurrency is opt-in in the user's program; the module stays usable single-threaded and on non-threaded Perl.
- **Keeping `initThread`** — dead, unexposed, single-callback; removed in V1.
