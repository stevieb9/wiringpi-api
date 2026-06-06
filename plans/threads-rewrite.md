# Plan: Rewrite the threads/concurrency story around a hands-off `worker()` helper

> **NEXT ACTION:** V12 — add a first-class `worker()` method to `RPi::WiringPi` (OO layer, **rpi-wiringpi** repo), mirroring its `background_interrupts` proxy. Start of Phase 2 (OO-layer parity). Execution order: V12 → V13 → V14 → V15 → V9 → V16.
> **LAST SESSION:** 2026-06-05. Audited the sibling `rpi-wiringpi` repo: the interrupt concurrency proxies were carried into the OO layer but **none** of the `worker()`/threads work was. Expanded this plan with Phase 2 (V12-V16) to give the OO layer first-class `worker()` parity, and re-scoped V9's `THREADS.pod` to document the new `$pi->worker` method as the headline. Phase 1 (V1-V8, V10, V11) remains complete in `WiringPi::API`.
> **ARCHIVE:** See threads-rewrite-archive.md for completed V tasks (V1-V8, V10-V11)

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
- **Changes bookkeeping**: every consumer-visible V task (new function, new option, doc-facing behaviour) appends a `Changes` bullet as part of that task's completion — not deferred to the verify task. **Phase 1 (`WiringPi::API`, this repo)** bullets go under `3.1801 UNREL` in this repo's `Changes`. **Phase 2 (`RPi::WiringPi`, sibling `rpi-wiringpi` repo)** bullets go under `3.1800 UNREL` in *that* repo's `Changes`.
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

## Phase 2 — OO-layer parity (`RPi::WiringPi`, sibling `rpi-wiringpi` repo)

Phase 1 shipped `worker()` in the low-level `WiringPi::API`. The sibling OO module
`RPi::WiringPi` carried over the **interrupt** concurrency proxies
(`background_interrupts`, `auto_dispatch_interrupts`, `run_interrupt_loop`,
`stop_interrupt_loop`, `stop_interrupts`) but has **no `worker()` surface at all**.
Phase 2 gives the OO layer the same first-class, hands-off `worker()` story.

Mirror the established sibling patterns exactly:

- The proxy lives in `lib/RPi/WiringPi.pm` next to `background_interrupts`, forwards
  to `WiringPi::API::worker()`, and lets the low-level layer do all argument
  validation (no duplicated croaks).
- Lifecycle is owned by the object: track each returned handle on `$self` and stop
  it in `RPi::WiringPi::Core::cleanup()` — beside the existing
  `WiringPi::API::stop_interrupts()` call — respecting the same forked-child guard
  (`$self->{proc} != $$`). `DESTROY` already routes through `cleanup`.
- Prereq is already satisfied: `rpi-wiringpi` requires `WiringPi::API` `3.1801`,
  which is the version shipping `worker()`. No prereq bump needed.
- `{mechanism=>'thread'}` bodies call `WiringPi::API::pi_lock`/`pi_unlock` directly
  (no new OO method); document this in `THREADS.pod` rather than wrapping it. Thread
  mode is a niche opt-in and the fork default never locks.

Off-Pi = parse/syntax/unit only; the full gate (build + `make test` + valgrind
exerciser) runs on the Pi, same as Phase 1's V8.

## Validation Table

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V12 | Add a `worker(\&body, \%opts)` proxy **method** to `lib/RPi/WiringPi.pm` (beside `background_interrupts`): forward to `WiringPi::API::worker()`, push the returned handle onto `$self->{workers}` (arrayref) for cleanup reaping, and return the handle. No duplicated validation — let `WiringPi::API` croak. Append a sibling `Changes` bullet under `3.1800 UNREL`. | (in rpi-wiringpi) `perl -c -Ilib lib/RPi/WiringPi.pm` | compiles; `$pi->worker(sub{...})` returns a `WiringPi::API::Worker` handle that is tracked on the object | ⏳ |
| V13 | Reap workers in `lib/RPi/WiringPi/Core.pm` `cleanup()`: after the forked-child proc-guard, idempotently `->stop` every handle in `$self->{workers}` and clear the list, beside the existing `WiringPi::API::stop_interrupts()`. A forked child (proc guard) must not stop the parent's workers. `DESTROY`/signal teardown inherit this via `cleanup`. Append a sibling `Changes` bullet. | (in rpi-wiringpi) `perl -c -Ilib lib/RPi/WiringPi/Core.pm` | compiles; `$pi->cleanup`/`DESTROY` stops tracked workers; child-process guard respected | ⏳ |
| V14 | Add `=head3 worker(\&body, \%opts)` POD to `lib/RPi/WiringPi.pm` near the interrupt methods: document the handle (`stop`/`pid`/`running`), the `once`/`interval`/`shared`/`results`/`mechanism` options, that `cleanup`/`DESTROY` auto-stops workers, and cross-ref `WiringPi::API`, `lib/WORKERS.pod`, and `THREADS.pod`. Append a sibling `Changes` bullet. | (in rpi-wiringpi) `podchecker lib/RPi/WiringPi.pm` | podchecker clean; `worker()` method documented | ⏳ |
| V15 | Add `t/NN-worker.t` to `rpi-wiringpi` (and MANIFEST), mirroring this repo's `t/85-worker.t`: off-Pi parts (proxy returns a handle of the right class, `WiringPi::API` validation croaks propagate, handle `stop` idempotency via a fork that writes to a channel, `cleanup` stops a tracked worker), plus a board-gated (`PI_BOARD`) GPIO block driving a real `$pi->worker` and confirming `cleanup` stops it. Append a sibling `Changes` bullet. | (in rpi-wiringpi) `prove -Ilib t/NN-worker.t` | off-Pi assertions pass; GPIO block runs under the board gate | ⏳ |
| V9 | Create `lib/THREADS.pod` in **rpi-wiringpi** documenting the OO threads/worker story, leading with the new `$pi->worker(...)` method (V12-V14) as the headline and demoting raw `fork`/`threads` to "under the hood"; match the voice/structure of the sibling's interrupt docs. `lib/WORKERS.pod` here is the reference; document `{mechanism=>'thread'}` bodies calling `WiringPi::API::pi_lock`/`pi_unlock` directly (no OO proxy — thread mode is a niche opt-in). Depends on V12-V14. | (in rpi-wiringpi) `podchecker lib/THREADS.pod` | accurate `THREADS.pod` matching the shipped OO `worker()` method | ⏳ |
| V16 | Full Pi gate for `rpi-wiringpi`: `perl Makefile.PL && make && make test`, plus an OO worker exerciser (`$pi->worker`) under `valgrind --leak-check=full` covering distinct-pin workers, a shared sampler read by main, periodic + once modes, stop/reap, cleanup-driven stop, and forgotten-stop END reaping — mirroring Phase 1's V8 + `valgrind_worker.pl`. | (in rpi-wiringpi, on Pi) `perl Makefile.PL && make && make test` + valgrind exerciser | full suite green; valgrind reports no worker-attributable leaks | ⏳ |

## Discovery Tracking

_None yet._

## Backlog

B1: `worker_pool([\&a, \&b, ...])` — one shared child servicing several workers (the `background_interrupts`-to-`background_interrupt` analogue), with per-worker `arm`/`disarm`. Only if a concrete multi-worker need appears.

B2: Bidirectional channel (parent → worker commands) so a running worker can be re-tasked without restart. Defer until a use-case needs it; `{once}`/restart covers most cases today.

B3: Review the `threads` wording in `rpi-wiringpi`'s `lib/RPi/WiringPi/FAQ.pod` (the "system Perl does not use threads" note) once `THREADS.pod` lands — cross-link to it and confirm the framing matches the fork-first `worker()` story. Non-blocking copy edit.

## Explicitly NOT doing

- **C-only `piThreadCreate2`/`thread_create`** — stays in parked `threads-patch.md` (B1/B2). Perl-in-a-shared-interpreter is unsafe; the ithread + fork mechanisms here cover the Perl cases.
- **Requiring `threads` / a threaded Perl in the dist** — `worker()` is fork-first; `use threads` is opt-in via `{mechanism=>'thread'}` only. The module stays usable single-threaded and on non-threaded Perl.
- **Reinventing ithreads in XS** (per-thread `perl_clone`, cross-interpreter SV marshalling) — duplicates core Perl badly.
- **Keeping the boilerplate scenarios as the headline** — the raw `threads->create`/`fork` patterns survive only as an "under the hood" reference behind `worker()`.
