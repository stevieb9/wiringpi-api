# Archive: Remove all traces of setup_phys() and setup_sys()

Completed tasks split out of clean-setup-calls.md. See that file for the live
Validation Table, rules and tracking. This plan is the detailed execution of
**V34** in UPGRADE-3.18.md.

## Archived V Tasks

- V1: API.xs — delete the `wiringPiSetupSys()` / `wiringPiSetupPhys()` XS wraps — ✅ 2026-06-04 attempt 1: PASS. Both removed; `wiringPiSetup()`/`wiringPiSetupGpio()` intact.
- V2: API.pm subs — delete `sub setup_sys`/`sub setup_phys` — ✅ 2026-06-04 attempt 1: PASS. Removed; `setup`/`setup_gpio` kept; `perl -c` OK.
- V3: API.pm exports — remove the two C names from `@wpi_c_functions` and the two Perl names from `@wpi_perl_functions` — ✅ 2026-06-04 attempt 1: PASS. qw() rows reflowed; `@EXPORT_OK`/tags derive from these arrays so no further export edits; `perl -c` OK.
- V4: API.pm POD — drop the EXPORT_OK POD tokens and the `=head2 setup_phys()`/`=head2 setup_sys()` blocks — ✅ 2026-06-04 attempt 1: PASS. Surrounding `setup_gpio()` POD reads correctly; podchecker shows only the pre-existing B8 issues.
- V5: README — remove the two names from the wrapper table and delete the `setup_phys()`/`setup_sys()` description blocks — ✅ 2026-06-04 attempt 1: PASS.
- V6: Delete `test/setup_phys.pl` — ✅ 2026-06-04 attempt 1: PASS. Whole file was a phys-mode test; not in MANIFEST or any runner; `git rm`'d.
- V7: Changes — BREAKING bullet at the bottom of the `3.1801 UNREL` section — ✅ 2026-06-04 attempt 1: PASS. "removed setup_sys()/setup_phys() and the wiringPiSetupSys/Phys wraps; only setup()/setup_gpio() remain"; historical entries untouched.
- V8: Mac static gate — ✅ 2026-06-04 attempt 1: PASS. No-traces sweep clean (only Changes + planning docs mention the names); `perl -c` OK; XS parses.
- V9: Pi build/run gate — ✅ 2026-06-04 attempt 1: PASS. Clean `perl Makefile.PL && make && make test` on `rpi1` — 54 tests pass, no `wiringPiSetupSys/Phys` link errors. Required resolving Fix 1 first (the F22 `interruptHandler` dangling symbol, which broke `make test` under `PERL_DL_NONLAZY` bind-now).
- V10: Downstream RPi::WiringPi — ✅ 2026-06-04 attempt 1: PASS (breakage-critical part). On a new `3.18` branch in `~/repos/rpi-wiringpi`, dropped the `/^p/` phys dispatch branch (`RPi/WiringPi.pm`) so it no longer calls the removed `setup_phys()` — verified by grep (no `SUPER::setup_phys`/`RPI_MODE_PHYS` in WiringPi.pm). This is `refactor-setup-modes.md` V1. The broader downstream cleanup (POD, `export_pin`/`unexport_pin`, SYS/PHYS scheme handling) continues under `refactor-setup-modes.md` V2-V9; full downstream test execution is gated on installing the upgraded WiringPi::API (UPGRADE-3.18.md **V33**).

## Archived Fixes

- Fix 1 (V9): `make test` failed under `PERL_DL_NONLAZY=1` (bind-now) on the dangling `interruptHandler` symbol (F22) — resolved by pulling UPGRADE-3.18.md V23's interruptHandler removal forward (deleted the dead XS export at API.xs + the API.h declaration; no C definition existed). `make test` then passed 54 tests. The remaining V23 parts (F7 pwm_set_range dedup, F8 lcd_char_def newline) stay with V23.
