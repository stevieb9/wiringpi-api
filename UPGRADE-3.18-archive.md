# Archive: Upgrade WiringPi::API to wiringPi 3.18

Completed tasks split out of UPGRADE-3.18.md to keep the active plan lean. See
that file for the live Validation Table, rules and tracking.

## Archived V Tasks

- V1: Board-map precheck (F9 gate) + baseline build against wiringPi 3.18 — ✅ 2026-06-04 attempt 1: PASS. Ran on `rpi1` (Raspberry Pi 5 / RP1, wiringPi 3.18). Build completed clean (exit 0, no warnings); `.so` loads. F9 gate cleared: new `t/20-board_map_precheck.t` cross-checks the custom `phys_wpi_map` against wiringPi's own tables (`wpi_to_gpio(phys_to_wpi(p)) == phys_to_gpio(p)`) and all 28 mapped header pins agree on this Pi5/RP1 — no blocking F# raised. F22 confirmed and reproduced: `interruptHandler` is an undefined symbol in the `.so` (not provided by wiringPi); calling it dies with `undefined symbol: interruptHandler` (already tracked → V23).

- V2: Fix camelCase export mismatches in `@wpi_c_functions` (`wpiToGpio`→`wpiPinToGpio`, `lcdDefChar`→`lcdCharDef`, `lcdPutChar`→`lcdPutchar`) — ✅ 2026-06-04 attempt 1: PASS. Confirmed the three broken names resolve to no XS sub and the corrected names exist (API.xs:346,419,425); fixed the three names in the export list plus a stray POD `lcdPutChar` reference (API.pm:1124). `perl -c` OK; every `@wpi_c_functions` name now resolves to an XS sub; the renamed names import and resolve to defined subs while the old names fail at `use`-time (the documented Public API impact). Full `t/` suite green (47 tests).

- V3: Implement `wiringPiVersion` XS (Option A, string) + snake_case `wiringpi_version` wrapper + POD — ✅ 2026-06-04 attempt 1: PASS. Confirmed 3.18 signature `void wiringPiVersion(int *major, int *minor)` (exported by lib, absent from our XS). Added a CODE block (`snprintf "%d.%d"` into a stack buf, returned as `char *` via T_PV copy) at the end of the core XS section; added `wiringpi_version` to `@wpi_perl_functions` (scalar = version string, list = `(major, minor)` pair via `wantarray`) with POD noting it reports the wiringPi *library* version, not the dist `$VERSION`. XS parses; `perl -c` OK. Built clean on `rpi1` (exit 0, no warnings); functional check returns scalar `"3.18"`, list `(3, 18)`, C-level `"3.18"`. New test `t/25-wiringpi_version.t` (added to MANIFEST, 7 assertions); full `t/` suite green (54 tests). podchecker shows only pre-existing issues (logged as B8), none introduced by V3.

## Archived Fixes
