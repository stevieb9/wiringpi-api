# Archive: threads-rewrite.md

Completed V tasks and resolved fixes for the `worker()` concurrency rewrite.
See threads-rewrite.md for the active plan.

## Archived V Tasks

- V1: `worker()` core (fork-based) + `WiringPi::API::Worker` handle — ✅ 2026-06-05 attempt 1: PASS
- V2: shared (`$w->value`) + results (`$w->read`/`$w->fh`) channels, length-framed over inherited pipes — ✅ 2026-06-05 attempt 1: PASS
- V3: pacing — `{interval => $secs}` (helper paces the loop) + `{once => 1}` (run body once, child exits) — ✅ 2026-06-05 attempt 1: PASS
- V4: opt-in ithread mechanism (`{mechanism => 'thread'}`) + `pi_lock`/`pi_unlock` key validation — ✅ 2026-06-05 attempt 1: PASS
- V5: POD — "CONCURRENCY / BACKGROUND WORKERS" section documenting `worker()`, options, handle, `pi_lock`/`pi_unlock`, setup-once contract + one-liner — ✅ 2026-06-05 attempt 1: PASS
- V6: rewrote `docs/threads-examples.md` to lead with `worker()`, demoted raw fork/threads/Async to "under the hood", un-parked, cross-linked; added `lib/WORKERS.pod` — ✅ 2026-06-05 attempt 1: PASS
- V7: extended `t/85-worker.t` with a `PI_BOARD`-gated GPIO block (worker drives BCM17, parent observes both levels + reaping; `{shared}` sampler reads the pin back via `value()`); off-Pi assertions already present, GPIO block self-skips without hardware — ✅ 2026-06-05 attempt 1: PASS
- V8: hardware-verified `worker()` on a Pi 5 (wiringPi 3.18) — `make test` PASS (279 tests, GPIO block drove BCM17 for real); added `testing/valgrind_worker.pl` exerciser, valgrind shows definitely/indirectly lost 0 (all errors are libperl baseline, confirmed against a load-only baseline) and no zombies; `{mechanism=>'thread'}` not run (non-threaded Perl) — ✅ 2026-06-05 attempt 1: PASS
- V10: fixed the `digital_write`/`digital_read` doc bug (non-exported names) -> `write_pin`/`read_pin` in the `worker()` POD synopsis, `lib/WORKERS.pod` and `docs/threads-examples.md`; byte variants untouched; `perl -c` + `podchecker` clean — ✅ 2026-06-05 attempt 1: PASS
- V11: applied the same `digital_write`/`digital_read` -> `write_pin`/`read_pin` fix to `docs/interrupt-examples.md` (function-reference table); `lib/INTERRUPTS.pod` already clean — ✅ 2026-06-05 attempt 1: PASS

## Archived Fixes

_None yet._
