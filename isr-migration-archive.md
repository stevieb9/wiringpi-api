# Archive: Migrate interrupts to `wiringPiISR2` via a self-pipe

Completed tasks split out of isr-migration.md to keep the active plan lean. See
that file for the live Validation Table, rules and tracking.

## Archived V Tasks

- V1: Prereq gate — confirm installed `<wiringPi.h>` declares `wiringPiISR2` / `wiringPiISRStop` / `struct WPIWfiStatus` (≥ 3.16) — ✅ 2026-06-04 attempt 1: PASS. Grepped `/usr/local/include/wiringPi.h` (the installed 3.18 header on `rpi1`; `/usr/include/wiringPi.h` is absent): `struct WPIWfiStatus` at :298, `wiringPiISR2` at :308 (tagged `// V3.16`), `wiringPiISRStop` at :309 (`//V3.2`). The `wiringPiISR2` prototype confirms the `void* userdata` parameter the self-pipe design keys on: `int wiringPiISR2(int pin, int edgeMode, void (*function)(struct WPIWfiStatus wfiStatus, void* userdata), unsigned long debounce_period_us, void* userdata)`. (`waitForInterrupt2` at :307 and the legacy `waitForInterruptClose` alias at :310 also present; per plan we wrap only `wiringPiISRStop`.) Precheck only — no code change.

- V2: Edge validation + constants (F23) — ✅ 2026-06-04 attempt 1: PASS. Added the four `INT_EDGE_*` constants (`use constant`: SETUP=0, FALLING=1, RISING=2, BOTH=3 — mirror wiringPi's `#define`s) and exported them via `@wpi_constants` → `:constants`/`:all`. Added ordered validation to the Perl `set_interrupt($pin, $edge, $callback)`: `$pin` positive integer, then `$edge` ∈ {1,2,3} (rejects SETUP=0 and junk — SETUP is a setup-only mode, not a trigger), then `$callback` a CODE ref; each croaks with a named message. (Validation placed in the Perl layer, not the soon-to-be-replaced XS `setInterrupt`; the XS keeps its own pin/callback checks as a backstop until V4.) `perl -c` OK; built clean on `rpi1` (no warnings); functional check: constants import as 0/1/2/3; edges 0/4/"x"/undef/1.5/-1 all rejected, bad pin/callback rejected in order. Changes entry deferred to V8 per this plan's maintenance model (V8 updates `3.1801 UNREL`). Discovery logged: examples/POD use `EDGE_RISING` vs the `INT_EDGE_*` chosen here — reconcile in V7/V8.

## Archived Fixes
