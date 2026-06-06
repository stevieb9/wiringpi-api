# Plan: Rewrite the threads/concurrency story around a hands-off `worker()` helper

> **NEXT ACTION:** V11 — apply the same `digital_write`/`digital_read` -> `write_pin`/`read_pin` fix to `docs/interrupt-examples.md` (function-reference table; `lib/INTERRUPTS.pod` already clean). (Then V9: `THREADS.pod` in the sibling rpi-wiringpi project, now unblocked.)
> **LAST SESSION:** 2026-06-05. V10 done: fixed the `digital_write`/`digital_read` doc bug (neither is exported; real subs are `write_pin`/`read_pin`) in the `worker()` POD synopsis (`lib/WiringPi/API.pm`), `lib/WORKERS.pod`, and `docs/threads-examples.md` — code, imports, prose, and signature tables. Byte variants (`digital_write_byte` etc.) untouched. `perl -c` + `podchecker` clean. Discovered the identical bug in `docs/interrupt-examples.md` (out of V10 scope) and logged it as V11.
> **ARCHIVE:** See threads-rewrite-archive.md for completed V tasks (V1-V8, V10)

## Goal

Make background/concurrent GPIO work require the **least possible user code**, the
same way the interrupt API does. Today `docs/threads-examples.md` is
boilerplate-heavy: every scenario hand-rolls `threads->create(sub {...})->detach`,
manual `:shared` declarations, `pi_lock`/`pi_unlock`, and an explicit loop. The
sibling `docs/interrupt-examples.md` instead leads with genuinely hands-off helpers
(`background_interrupt`, `auto_dispatch_interrupts`, an idempotent `$h->stop`) and
demotes the raw plumbing to "under the hood" sections.

Deliver the same for general background work:

1. A **`worker()`** helper that hides the spawn mechanism, the loop, and the
   lifecycle. Fork-based by default (works on any Perl, **no `use threads`**),
   returning an idempotent handle (`stop`/`pid`/`running`) — a direct sibling of
   `background_interrupt`.
2. **Shared latest-value** and **results** channels so a worker can hand data back
   to main without the user writing IPC or `:shared` plumbing.
3. **Periodic / one-shot pacing** (`{interval => $s}`, `{once => 1}`) so the common
   "blink / sample every N seconds" worker is a one-liner.
4. An **opt-in ithread mechanism** for users who specifically want shared-memory
   ergonomics on a threaded Perl — kept as a documented alternative, not the
   headline.
5. A **full rewrite of `docs/threads-examples.md`** that leads with `worker()`,
   demotes raw `threads->create`/`fork` to "under the hood," un-parks the doc, and
   matches the structure/voice of `interrupt-examples.md`.
6. **POD + tests + hardware verification.**

## Design (the hands-off contract)

Mirror `background_interrupt` exactly — same shape, same handle semantics, same
END-reaper safety net (`@_bg_children` / `WiringPi::API::BackgroundInterrupt`).

```perl
use WiringPi::API qw(setup pin_mode digital_write worker);

setup();
pin_mode(2, 1);                                   # OUTPUT, once in main

# Heartbeat LED — helper owns the loop AND the lifecycle. No use threads, no fork,
# no detach, no while(1):
my $w = worker(sub { digital_write(2, 1); sleep 1; digital_write(2, 0); sleep 1 });

# ... main does its own work ...

$w->stop;                                         # idempotent; END reaps if forgotten
```

Proposed surface (final signatures fixed in V1, written into the rewritten doc):

- `worker(\&body, \%opts)` → forks a child, runs `body` **repeatedly** by default,
  returns a `WiringPi::API::Worker` handle.
  - Handle: `stop` (idempotent), `pid`, `running` — same as the interrupt handle.
- `\%opts`:
  - `{once => 1}` — run `body` a single time, not in a loop.
  - `{interval => $secs}` — pace the loop (periodic sampler/blink) instead of
    letting `body` set its own cadence.
  - `{shared => 1}` — publish `body`'s return value as a **lossy latest value**;
    parent reads it with `$w->value` (the `Async::Event::Interval->shared_scalar`
    idea, framed over a pipe like the interrupt `results` channel).
  - `{results => 1}` — stream every defined return value back; parent drains with
    `$w->read` / selects on `$w->fh` (identical to `background_interrupt`'s
    `{results=>1}`).
  - `{mechanism => 'fork'|'thread'}` — default `fork` (no threaded Perl needed);
    `thread` uses an ithread for shared-memory ergonomics and requires `threads`
    to be loaded (croak with a clear message otherwise).

Validate every argument **before** forking — never fork into a guaranteed failure
(the existing `background_interrupt` rule). `body` must be a CODE ref; `interval`
a positive number; `mechanism` one of the two known values; etc.

## Relationship to the parked `threads-patch.md`

`threads-patch.md` is parked and predates this. This plan **supersedes its
doc/helper aims** (its V3 "document the contract" and backlog B3 "encapsulate the
interrupt-ithread boilerplate" — `background_interrupt` already covers the latter).
Its `pi_lock`/`pi_unlock` wrappers (V2) are still wanted for the opt-in ithread
mechanism and are folded in here (V5). Its C-only `piThreadCreate2` backlog
(B1/B2) is **out of scope** and stays in that plan. When this plan lands, mark
`threads-patch.md` superseded.

## Validation environment

**Pi-only** for build/run; off-Pi is parse/syntax/unit only.

- **Quick checks (off-Pi):** `perl -c -Ilib lib/WiringPi/API.pm`;
  `podchecker lib/WiringPi/API.pm`; targeted `prove` of the new `t/` worker test
  for the parts that don't touch real GPIO (validation croaks, handle/stop
  idempotency, pipe framing via a fork that writes to the channel).
- **Full gate (Pi):** `perl Makefile.PL && make && make test`, plus a worker
  exerciser under `valgrind --leak-check=full` (distinct-pin workers, a shared
  sampler read by main, periodic + once modes, stop/reap, forgotten-stop END
  reaping).

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all three:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of threads-rewrite-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
  3. **Delete the V# row from this file's Validation Table.**
- V task ❌: update Actual with `❌ YYYY-MM-DD attempt N: reason`. Rerun same V# with attempt N+1. Do NOT create a new V#.
- **Changes bookkeeping**: every consumer-visible V task (new function, new option, doc-facing behaviour) appends a `Changes` bullet under `3.1801 UNREL` (at the bottom of the section, capitalized) as part of that task's completion — not deferred to the verify task.
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
| V9 | **(HOLD)** Create `THREADS.pod` in the **rpi-wiringpi** project documenting that project's threads/worker story, written to match `WiringPi::API`'s `worker()` implementation here (the `lib/WORKERS.pod` guide is the reference). Unblocked now V1-V8 are implemented and hardware-verified; do after V10 so the reference docs it mirrors are corrected first. | (in rpi-wiringpi) `podchecker THREADS.pod` once unblocked | accurate `THREADS.pod` matching the shipped `worker()` API | ⏳ |
| V11 | **Doc bug (interrupt docs).** Same `digital_write`/`digital_read` -> `write_pin`/`read_pin` fix in the non-worker consumer docs: `docs/interrupt-examples.md` (the function-reference table at the bottom) uses the non-existent names. (`lib/INTERRUPTS.pod` is already clean.) | `grep -rnE 'digital_(write\|read)([^_]\|$)' docs/interrupt-examples.md lib/INTERRUPTS.pod` | interrupt docs use the real exported names | ⏳ |

## Discovery Tracking

_None yet._

## Backlog

B1: `worker_pool([\&a, \&b, ...])` — one shared child servicing several workers (the `background_interrupts`-to-`background_interrupt` analogue), with per-worker `arm`/`disarm`. Only if a concrete multi-worker need appears.

B2: Bidirectional channel (parent → worker commands) so a running worker can be re-tasked without restart. Defer until a use-case needs it; `{once}`/restart covers most cases today.

## Explicitly NOT doing

- **C-only `piThreadCreate2`/`thread_create`** — stays in parked `threads-patch.md` (B1/B2). Perl-in-a-shared-interpreter is unsafe; the ithread + fork mechanisms here cover the Perl cases.
- **Requiring `threads` / a threaded Perl in the dist** — `worker()` is fork-first; `use threads` is opt-in via `{mechanism=>'thread'}` only. The module stays usable single-threaded and on non-threaded Perl.
- **Reinventing ithreads in XS** (per-thread `perl_clone`, cross-interpreter SV marshalling) — duplicates core Perl badly.
- **Keeping the boilerplate scenarios as the headline** — the raw `threads->create`/`fork` patterns survive only as an "under the hood" reference behind `worker()`.
