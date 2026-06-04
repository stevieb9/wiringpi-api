# Archive: Upgrade WiringPi::API to wiringPi 3.18

Completed tasks split out of UPGRADE-3.18.md to keep the active plan lean. See
that file for the live Validation Table, rules and tracking.

## Archived V Tasks

- V1: Board-map precheck (F9 gate) + baseline build against wiringPi 3.18 — ✅ 2026-06-04 attempt 1: PASS. Ran on `rpi1` (Raspberry Pi 5 / RP1, wiringPi 3.18). Build completed clean (exit 0, no warnings); `.so` loads. F9 gate cleared: new `t/20-board_map_precheck.t` cross-checks the custom `phys_wpi_map` against wiringPi's own tables (`wpi_to_gpio(phys_to_wpi(p)) == phys_to_gpio(p)`) and all 28 mapped header pins agree on this Pi5/RP1 — no blocking F# raised. F22 confirmed and reproduced: `interruptHandler` is an undefined symbol in the `.so` (not provided by wiringPi); calling it dies with `undefined symbol: interruptHandler` (already tracked → V23).

## Archived Fixes
