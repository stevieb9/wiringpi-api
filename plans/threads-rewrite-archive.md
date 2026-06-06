# Archive: threads-rewrite.md

Completed V tasks and resolved fixes for the `worker()` concurrency rewrite.
See threads-rewrite.md for the active plan.

## Archived V Tasks

- V1: `worker()` core (fork-based) + `WiringPi::API::Worker` handle — ✅ 2026-06-05 attempt 1: PASS
- V2: shared (`$w->value`) + results (`$w->read`/`$w->fh`) channels, length-framed over inherited pipes — ✅ 2026-06-05 attempt 1: PASS
- V3: pacing — `{interval => $secs}` (helper paces the loop) + `{once => 1}` (run body once, child exits) — ✅ 2026-06-05 attempt 1: PASS
- V4: opt-in ithread mechanism (`{mechanism => 'thread'}`) + `pi_lock`/`pi_unlock` key validation — ✅ 2026-06-05 attempt 1: PASS

## Archived Fixes

_None yet._
