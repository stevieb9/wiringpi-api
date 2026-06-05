# Plan: Upgrade WiringPi::API to wiringPi 3.18

> **NEXT ACTION:** V26 — **`serialGets` (F13, CRITICAL)**: fix the heap buffer overflow (Perl passes a 0-length scalar, C writes up to `nbytes`). Rewrite as a self-allocating XSUB (`Newx`/`Safefree`, `newSVpvn`), `croak` not `exit(-1)`. Read semantics settled with user 2026-06-05 (see V26 row). (Phase 4 hold lifted; remaining: V26/V27/V31 real work, V28/V29/V30 close by reference, V32 final valgrind gate, then V36.)
> **LAST SESSION (2026-06-05):** Ran **V33 — Downstream gate — PASS** (verifiable scope). **Executable-stack blocker RESOLVED:** root cause was the old `initThread` GCC nested function (stack trampoline → RWE `.so`); the ISR migration removed it, current build is clean `GNU_STACK ... RW`, `make install` propagated it → installed WiringPi::API 3.1801 loads. Downstream suite (PERL5LIB = working-tree rpi-wiringpi + rpi-pin libs, RPi::Pin 2.3609 coderef-ISR): interrupt assertions PASS 3/3 (rising/falling/both via new coderef API), `t/105` PASS + `t/106` pin-translation PASS, `shift_reg_setup`/`i2c_setup` croaks confirmed. Bumped rpi-wiringpi `Makefile.PL` prereq 2.3616→3.1801 + Changes (working tree, uncommitted). **Residuals:** serial_gets memory-safety gated on V26 (Phase 4 HOLD); device-wired runtime (shift_reg/serial/i2c round-trip) skips — no wired devices (i2c → B10); subsidiary dists not checked out; the 17 `rpi_check_pin_status` failures per interrupt/pin-map suite are pre-existing orthogonal board-config drift (user-owned, NOT a regression — do not "fix"). Earlier same day: **V25 Phase 3 full gate PASS** (230 tests, clean build) → Phase 3 complete; **V13 PASS by reference** → Phase 2 complete. **Added V36** (final regression gate). Standing flags: Phase 4 V26-V32 ⏸ HOLD; B5/B7/B9/B10; commits pending in all three repos; rpi-wiringpi cleanup under `refactor-setup-modes.md` V2-V9.
> **ARCHIVE:** See UPGRADE-3.18-archive.md for completed V tasks (V1-V25, V33-V35 archived)

## Goal

The distribution currently wraps an older wiringPi (the POD/Makefile reference
2.36+). Upstream is now **3.18** (`~/repos/wiringPi`, `VERSION` = 3.18). Bring
this XS module fully in line with 3.18 in three phases:

- **Phase 1 — Compatibility (V1–V7, plus V34):** make every call we *already* wrap build,
  link and behave correctly against 3.18; fix broken exports and stale version
  metadata.
- **Phase 2 — Coverage (V8–V17):** wrap useful 3.18 calls we don't expose yet
  (including functions already present in the XS but missing a Perl layer).
- **Phase 3 — Quality (V18–V25):** fix the bugs and efficiency issues found in
  the Perl and XS code during the planning review (logged as F1–F10 below), plus
  a formal review pass.

## Validation environment

**This machine IS the validation Pi.** Confirmed 2026-06-04: hostname `rpi1`, a
**Raspberry Pi 5 Model B Rev 1.1** (revision `d04171`, **RP1** present —
`rp1_firmware`/`rp1_vdd_3v3` in the device tree), with the full toolchain
installed:

- wiringPi **3.18** (`gpio version: 3.18`)
- headers at `/usr/local/include/wiringPi.h`; libs `libwiringPi.so.3.18` +
  `libwiringPiDev.so.3.18` in `/usr/local/lib`
- gcc 14.2.0, GNU Make 4.4.1, perl 5.42.0 (aarch64)

So **every task here runs on this box** — the build/link/test full gates (V7,
V17, V25), the board-map precheck (V1), and the Phase 4 `valgrind`/`helgrind`
work all execute locally. (The earlier "nothing runs on the current machine"
caveat assumed a different dev box and no longer applies.) Note: this is a
**Pi 5 / RP1** — precisely the board F9/V1 flag as the highest risk for
`phys_wpi_map`/`physPinToWpi` correctness. Two tiers of check:

- **Quick checks** (fast iteration while editing, before a full build):
  - Perl syntax: `perl -c -Ilib lib/WiringPi/API.pm` (the `XSLoader::load` is a
    runtime statement, so `-c` does not need the compiled `.so`).
  - POD: `podchecker lib/WiringPi/API.pm` and `prove -Ilib t/pod.t`.
  - XS parse (catches XS/typemap syntax errors before compiling):
    `perl -MExtUtils::ParseXS=process_file -e 'process_file(filename=>"API.xs", output=>"/tmp/API_check.c")'`
- **Full gate** (phase exit): `perl Makefile.PL && make && make test` — the real
  compile, link and test against wiringPi 3.18 and any attached hardware, run
  here on `rpi1`. Tasks marked **Full gate** are the phase exit criteria.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all four:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of UPGRADE-3.18-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
  3. **Delete the V# row from this file's Validation Table.**
  4. **Add a Changes entry** at the bottom of the current `3.1801 UNREL` section for any consumer-visible change (new/fixed/changed function, behavior, exports, tests). Skip only for purely internal no-ops (e.g. a precheck that changed no code); when skipping, note why in the archive bullet.
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

### Phase 1 — Compatibility (make existing wraps work on 3.18)

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|

### Phase 2 — Coverage (wrap 3.18 calls we don't expose yet)

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|

### Phase 3 — Quality (bugs & efficiency in Perl + XS)

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|

### Phase 4 — Custom-XS behavior audit & hardening (HOLD LIFTED 2026-06-05 — working live on the Pi)

> **Hold lifted 2026-06-05 (user).** This phase audits the hand-written C in API.xs
> (`serialGets`, `spiDataRW`, the interrupt dispatcher/threads, `physPinToWpi`)
> for correctness, leaks, races and intent. Worked **live on `rpi1`** (hardware +
> `valgrind`). Note several rows are already **dissolved/resolved** by the
> interrupt migration + threads-patch and will close mostly by reference:
> V28/V29 (F17/F18/F19 — the dispatcher/`perl_callbacks[]` they target no longer
> exist after the self-pipe redesign) and V30 (F20 — `initThread`/the GCC nested
> function already removed; that nested function was the V33 executable-stack root
> cause). V26/V27/V31 are the real remaining code work.
>
> **Open intent questions to settle live:**
> - `serialGets` read semantics — block-until-`nbytes` (current) vs read-what's-available vs block-with-timeout; how to report EOF / partial reads (partial string, `undef`, or `croak`); text vs binary payloads.
> - Interrupt teardown — the shape of the public stop/clear API (V29) — largely settled by the shipped `stop_interrupt`/`stop_interrupts`.

| ID | What | Command (run on the Pi) | Expected | Actual |
|----|------|-------------------------|----------|--------|
| V26 | **`serialGets` (F13, CRITICAL)** — heap buffer overflow: the Perl wrapper passes a 0-length scalar (`my $buf = ""`, API.pm:111) but the C writes up to `nbytes` into it (API.xs:32-48) → out-of-bounds heap write. Rewrite as a self-allocating XSUB (`Newx`/`Safefree`, return `newSVpvn(buf, n)`); replace `exit(-1)` with `croak`. **Confirm intent live:** read semantics + EOF/partial handling | `valgrind --leak-check=full perl -Iblib/lib -Iblib/arch test/serial_pi.pl` | no OOB write, no leak; agreed semantics | ⏳ |
| V27 | **`spiDataRW` (F14/F15/F16)** — NULL-check `av_fetch` before deref (sparse/undef element → crash, API.xs:80-82); compute `SvNV(*elem)` once not twice (API.xs:82,89); drop the VLA for `Newx`/`Safefree`; `croak` instead of `exit(1)`; replace the `dXSARGS`-inside-plain-C + `PL_markstack_ptr` juggling (API.xs:96-104, 540-549) with an idiomatic PPCODE XSUB | `valgrind --leak-check=full perl -Iblib/lib -Iblib/arch test/<spi script>` | no crash on sparse/empty aref; no leak | ⏳ |
| V28 | **Interrupt thread-safety (F17/F18)** — the dispatcher reads `perl_callbacks[pin]`/`SvRV` (API.xs:163-170) with no lock while `setInterrupt` `SvREFCNT_dec`s + replaces it (API.xs:215-217) → use-after-free. Guard `perl_callbacks[]` with a mutex, store via `newSVsv`; wrap dispatcher `call_sv` in `G_EVAL` so a dying callback can't croak across the worker thread. **Superseded 2026-06-03 by the self-pipe redesign (`isr-migration.md`)** — removing the cross-thread `perl_callbacks[]` table + dispatcher *designs out* F17/F18 rather than fixing them | `valgrind --tool=helgrind perl -Iblib/lib -Iblib/arch testing/interrupt.pl` | no UAF/race; callback death contained | ⏳ |
| V29 | **Interrupt lifecycle/cleanup (F19)** — the dispatcher thread is never shut down or joined (`dispatcher_shutdown` only ever set to 0; no signal/join, API.xs:130-131,221-226) and `wiringPiISRStop` is never called → thread + ISR + held callback SVs leak at teardown. Add a teardown (set shutdown, signal cond, `pthread_join`, `wiringPiISRStop` per pin [V13], `SvREFCNT_dec` callbacks) exposed as `stop_interrupts`/`clear_interrupt`. **Superseded 2026-06-03 by the self-pipe redesign (`isr-migration.md`)** — no dispatcher thread to join; teardown is just `wiringPiISRStop` per pin + closing the pipe (its V6) | `valgrind --leak-check=full perl -Iblib/lib -Iblib/arch testing/interrupt.pl` | thread joined; no leaked thread/SV/ISR | ⏳ |
| V30 | **`initThread` (F20)** — single global `thread_callback_sv` allows only one callback and shares the same replace/read race; `PI_THREAD(myThread){...}` uses a GCC nested function as the thread entry (non-standard C). API.xs:231-259. **Resolved 2026-06-03 in `threads-patch.md`:** the dead `initThread` is removed (its V1) and concurrent Perl is handled via Perl ithreads (documented contract), **not** by running Perl in C-spawned threads; the `piThreadCreate2` userdata patch is demoted to that plan's Backlog (C-only workers) | review + `make` (watch for warnings) | decision recorded; compiles clean | ⏳ |
| V31 | **`physPinToWpi` (F21)** — `physPinToWpi(p)` indexes `phys_wpi_map[64]` with no bounds check (API.xs:261-263) → OOB read for `p<0` or `p>=64`. Return -1 (the map's "non-existent" sentinel) for out-of-range and mirror the guard in the Perl `phys_to_wpi` wrapper | `perl -c -Ilib lib/WiringPi/API.pm` + out-of-range unit test | returns -1; no OOB read | ⏳ |
| V32 | **Full leak/behaviour gate** — build with debug and run every custom-XS path under `valgrind --leak-check=full` (and `helgrind` for the threads) via the testing/ scripts; confirm no leaks, races or UB across serialGets/spiDataRW/interrupts/initThread | `valgrind --leak-check=full --show-leak-kinds=all perl -Iblib/lib -Iblib/arch testing/interrupt.pl` (and sr/thread/serial scripts) | all clean | ⏳ |

### Cross-repo — Downstream verification (RPi::WiringPi)

| ID | What | Command (run on the Pi) | Expected | Actual |
|----|------|-------------------------|----------|--------|

### Final — full regression gate (run LAST, after all other work)

| ID | What | Command (run on the Pi) | Expected | Actual |
|----|------|-------------------------|----------|--------|
| V36 | **Final regression gate** — re-run the V25 full gate once **every other ⏳/⏸ task is done** (V33 downstream + any un-held Phase 4 V26-V32 + the installed-module executable-stack fix). Clean `make realclean && perl Makefile.PL && make` (no warnings), `PI_BOARD=1 make test` (all hardware paths), podchecker (API.pm + INTERRUPTS.pod), and live board sanity; confirm Changes still current for anything landed after V25. This is the last thing before release. | `make realclean && perl Makefile.PL && make && PI_BOARD=1 make test` (on Pi) + podchecker + live sanity | all green; no warnings; Changes current | ⏳ (blocked: run only after all other tasks complete) |

## Public API impact (consumer-facing)

What changes for code that `use`s WiringPi::API, directly or via RPi::WiringPi.

**Most consumers are unaffected.** The snake_case Perl wrappers (`read_pin`,
`write_pin`, `pin_mode`, `lcd_*`, `i2c_*`, `serial_*`, `spi_*`, etc.) keep the
same names and call signatures throughout, and the OO interface (`->new` +
methods) is unchanged. Phase 2 is purely additive. The items below are the only
consumer-visible changes.

**Backward-compatible (nothing that works today breaks):**

- **New exported functions** (Phase 2, V8–V16) — additions to `@EXPORT_OK` and the
  `:all` / `:perl` / `:wiringPi` tags. Only theoretical risk: a `:all` consumer who
  already defined a same-named sub (the standard `:all` caveat).
- **`wiringPiVersion` starts working** (V3) — today it is exported but undefined, so
  calling it dies; it returns the wiringPi *library* version as a `"3.18"` string
  (Option A), so no working code depends on the new shape.
- **`i2c_interface` starts working** (V14) — previously always croaked "not available".
- **`i2c_setup` accepts more addresses** (V19) — addresses it wrongly rejected now
  succeed; no previously-valid call starts failing.
- **XS error paths croak instead of `exit()`** (V21) — `serial_gets` / `spi_data`
  errors become catchable instead of killing the whole process.

**Behavior / signature changes to call out (could affect a consumer):**

- **`setup_sys` / `setup_phys` removed — BREAKING** (V34): `wiringPiSetupSys()` /
  `wiringPiSetupPhys()` and their Perl wrappers `setup_sys()` / `setup_phys()` are
  deleted (XS, exports, POD). Only `setup()` (`wiringPiSetup`, wiringPi numbering)
  and `setup_gpio()` (`wiringPiSetupGpio`, BCM) remain. Calling a removed name dies;
  an `:all`/explicit import of it fails at `use` time. **Breaks RPi::WiringPi**
  (`RPi/WiringPi.pm:52` calls `setup_phys()`) — see Downstream verification.

- **`$VERSION` jumps 2.3617 → 3.1801** (V6). A `use WiringPi::API 2.36xx` lower
  bound is still satisfied (3.18 > 2.36), but the 2.x→3.x scheme change matters for
  downstream version pins — notably **RPi::WiringPi**. Treat it as the major-bump
  signal it is.
- **Three broken camelCase exports renamed** (V2): `wpiToGpio` → `wpiPinToGpio`,
  `lcdDefChar` → `lcdCharDef`, `lcdPutChar` → `lcdPutchar`. The old names are in
  `@EXPORT_OK` / `:wiringPi` / `:all` today but map to no real sub (import
  succeeds, the *call* dies). After the rename, importing an old name fails at
  `use` time instead. Only affects code using the never-functional old names; the
  snake_case equivalents (`wpi_to_gpio`, `lcd_char_def`, `lcd_put_char`) are
  unchanged. *Option:* keep the old names as working aliases — see **B6**.
- **`i2c_read_word` return value changes** (V18). It currently returns an 8-bit
  read (`ReadReg8`); the fix returns the full 16-bit word. Consumers that
  unknowingly relied on the truncated value will see different numbers.
- **`shift_reg_setup` now croaks on out-of-range input** (V20) that the broken
  `&&` guard previously let pass through to the C layer.
- **`lcd_char_def` no longer writes a stray newline** to the display before
  defining the character (V23) — visible only if a consumer relied on that
  side effect.
- **Undocumented no-op `interruptHandler()` removed** (V23) — not exported, not
  documented; negligible.

**Phase 4 (custom-XS hardening — on hold for live Pi work):** mostly internal.
Consumer-visible bits: `serial_gets` will stop corrupting memory / killing the
process and will `croak` on a read error instead; `phys_to_wpi` will return -1
for out-of-range input instead of reading out of bounds; a new interrupt-teardown
function (e.g. `stop_interrupts`) may be added (additive). The `set_interrupt`,
`spi_data` and `serial_gets` call signatures are unchanged.

## Downstream verification (RPi::WiringPi + subsidiaries)

**Hybrid split:** the test/impact matrix below lives here (it's a release gate of
this upgrade); the actual edits to RPi::WiringPi and each subsidiary dist are made
and committed in *those* repos, cross-linked back to this plan. The active gate is
**V33**.

**Coupling:** `RPi::WiringPi::Core` and `::Util` both `use parent 'WiringPi::API'`
(RPi::WiringPi *is-a* WiringPi::API), and its `Makefile.PL` pins
`WiringPi::API => 2.3616`. Its own `lib/` only calls `shift_reg_setup`,
`pwm_set_range` and the camelCase `pwm*`/`pinModeAlt`/`digitalWrite` directly — but
its **`t/` suite is a full-stack integration harness** that, run on the Pi against
an installed upgraded module, transitively exercises the i2c/lcd/serial/spi/adc
paths through the installed subsidiary dists. That suite is the single best
downstream gate (hardware-dependent — tests skip where the device isn't wired).

**Scope caveat — subsidiaries aren't checked out here.** Only `rpi-wiringpi`,
`WiringPi` (upstream C) and `wiringpi-api` live under `~/repos`; the device dists
(RPi::I2C, RPi::SPI, RPi::LCD, RPi::ADC::*, RPi::DAC::*, RPi::BMP180, RPi::DHT11, …)
are separate repos. Enumerate their call sites and open a per-repo Changes entry
when discovered on the Pi.

### Test-coverage matrix — our change → RPi::WiringPi exerciser

| Change (V/F) | RPi::WiringPi exerciser | What to verify |
|--------------|-------------------------|----------------|
| V20 `shift_reg_setup` | `t/335-shift_reg_adc.t`, `lib/RPi/WiringPi.pm:298`, `build_testing/shift.pl` | valid args unchanged; out-of-range now croaks |
| V23 `pwm_set_range` | `t/109-pwm_hw_mods.t`, `t/140-pwm_spi_adc.t`, `t/325-servo.t`, `Core.pm:107`, `build_testing/api_servo.pl` | output identical (de-dupe only) |
| V23 `lcd_char_def` | `t/925-lcd.t`, `build_testing/build/wpi_char_def.pl`, `build_testing/build/lcd_char_def.pl` | no stray newline before glyph |
| V18 `i2c_read_word` | `t/305-i2c.t`, `t/320-rtc.t`, `t/340-bmp.t`, `t/345-dpot.t` (via I2C subsidiaries) | full 16-bit word; fix any caller that relied on the 8-bit value |
| V19 `i2c_setup` | `t/305-i2c.t`, `t/300-i2c_exceptions.t` | 0x48/72 now accepted; junk croaks |
| V14 `i2c_interface` | `t/305-i2c.t` | no longer croaks "not available" |
| V21 / V26 `serial_gets` | `t/315-serial.t` | catchable croak; **no heap overflow** (F13) |
| V13 / V24 interrupts (F12/F17-F19) | `t/200-interrupt_rising_and_pud.t`, `t/201-...falling...`, `t/202-...both...`, `build_testing/build/defacto_interrupt.pl` | rising/falling/both fire; clean teardown, no UAF |
| V11 `getPinModeAlt`/`pinModeAlt` | `t/107-alt_modes.t`, `t/108-mode_state_all_pins.t`, `build_testing/alt_mode.pl` | alt reads/writes correct |
| F9 / F21 / V24 / V31 `phys_wpi_map` | `t/105-pin.t`, `t/106-pin_map.t` | pin translation correct on this Pi/RP1 |
| F11 / B7 `bmp180Pressure`/`Temp` | `t/340-bmp.t`, `build_testing/bmp.pl` | raw reads unchanged |
| V6 `$VERSION` 2.36→3.18 | install / `Makefile.PL` prereq | bump prereq 2.3616→3.1801 (downstream edit) |
| V34 `setup_sys`/`setup_phys` removed | `RPi/WiringPi.pm:51-54` (phys branch), POD refs (`Core.pm:512,518`; `WiringPi.pm:898,902`) | phys init path dropped/redirected; no calls to removed subs; POD mentions of `setup_sys()` cleaned — tracked by `refactor-setup-modes.md` (V1/V4) in the rpi-wiringpi repo |

### Required downstream changes (committed in the consumer repos)

- **RPi::WiringPi `Makefile.PL`** — bump prereq `WiringPi::API => 2.3616` →
  `3.1801` when you want to *require* the fixes (install is already satisfied since
  3.18 > 2.36). Tracked + committed in the rpi-wiringpi repo.
- **RPi::WiringPi code** — **V34 forces one change:** it calls `setup_phys()`
  (`RPi/WiringPi.pm:52`), which V34 removes — drop/redirect the `/^p/` phys branch
  (`RPi/WiringPi.pm:51-54`) and clean the POD mentions of `setup_sys()` (`Core.pm:512,518`;
  `WiringPi.pm:898,902`). **This downstream edit is now tracked in the rpi-wiringpi
  repo by its `refactor-setup-modes.md` plan** — its V1 drops the `/^p/` phys dispatch
  branch (`RPi/WiringPi.pm:51-54`), V4 cleans the `setup_sys()`/`setup_phys()` POD in
  `Core.pm` + `WiringPi.pm`. Otherwise none forced: it uses no renamed export, and its
  `shift_reg_setup` / `pwm_set_range` / `lcd_char_def` calls stay source-compatible
  (only `shift_reg_setup`'s *error* path tightens). Re-run `t/` to confirm.
- **Subsidiary dists (TODO — discover on the Pi)** — the i2c/lcd/serial changes
  (V18 return width, V19 validation, V2 renames) land wherever the sibling dists
  call them; enumerate each repo's call sites and track the edit in that repo.

## Custom functions — obsolescence & duplication

Functions hand-written in WiringPi::API (beyond thin 1:1 XS wraps), and whether
the calls wrapped in Phase 2 make them redundant.

**May become redundant / simplifiable once Phase 2 lands:**

- **Custom interrupt trampolines + global callback array** (API.xs:111-229:
  `MAKE_HANDLER`/`APPLY_TO_PINS` generate 40 per-pin handlers, plus
  `perl_callbacks[MAX_PINS]` and the event-queue dispatcher). They exist only to
  work around `wiringPiISR()`, whose callback takes no argument — a per-pin
  trampoline is the only way to know which pin fired. **`wiringPiISR2()` (V13)
  adds a `void *userdata` parameter** that can carry the Perl callback SV (and the
  pin) directly, so the 40 trampolines + global array can collapse into one
  generic handler. Internal refactor only — `set_interrupt`'s public signature
  stays. Tracked as **F12**, evaluated in **V24**.
- **XS `bmp180Pressure` / `bmp180Temp`** (API.xs:265-271) are literally
  `return analogRead(pin);` — duplicates of `analogRead` on the bmp180 pseudo-pins.
  They're exported (API.pm:26-27) and POD-documented as the "raw value" accessors,
  so they can't simply be deleted, but they add nothing over
  `analog_read($base + 0/1)`. Tracked as **F11** / **B7** (deprecate + document,
  don't break consumers).

**Custom but NOT obsoleted — keep (no 3.18 equivalent exists):**

- **`serialGets`** (API.xs:32-48) — wiringPi 3.18 still offers only `serialGetchar`
  (one byte) in wiringSerial.h; there is no native multi-byte read. Keep.
- **`spiDataRW`** (API.xs:50-105) — Perl-arrayref ↔ `unsigned char *` marshalling
  glue around `wiringPiSPIDataRW`; inherently Perl-specific, nothing upstream
  replaces it. Keep.
- **`physPinToWpi` + `phys_wpi_map`** (API.xs:261-263, API.h:64-99) — 3.18 exposes
  `wpiPinToGpio` and `physPinToGpio` but **no phys→wpi mapping**, so this custom
  table is still required. It does duplicate board-layout data wiringPi owns and
  may be wrong for Pi5/RP1 — that is the **F9** / **V24** / **B5** maintenance
  risk, not obsolescence.

**Already dead (not "becoming" obsolete — it already is):**

- **`interruptHandler()`** (API.xs:489-490) — no-op leftover from the
  pre-dispatcher design; removal is **F10** / **V23**.

## Discovery Tracking

(none open)

## Review Findings

Concrete issues already spotted during the planning read-through. F1–F8 have
dedicated Phase 3 V tasks; F9–F10 are folded into V24/V23. New findings from the
V24 review pass append here as F11+.

- **F1** (→V18): `i2c_read_word` reads an 8-bit register (`wiringPiI2CReadReg8`) where it should read 16-bit (`wiringPiI2CReadReg16`). API.pm:398. Functional bug — returns half the word.
- **F2** (→V19): `i2c_setup` regex `^\d$` only matches a single digit; every multi-digit I2C address is rejected. API.pm:353.
- **F3** (→V20): `shift_reg_setup` uses `$num_pins < 0 && $num_pins > 32` (and the same pattern in the pin loop) — `&&` can never be true, so validation never fires. Should be `||`. API.pm:333, 337-338.
- **F4** (→V21): XS `serialGets` calls `exit(-1)` on a read error, terminating the whole Perl process. API.xs:40. Should `croak`.
- **F5** (→V21): XS `spiDataRW` calls `exit(1)` on an out-of-range byte and uses a VLA (`unsigned char buf[num_bytes]`). API.xs:75, 85-86. Should `croak`; avoid the VLA.
- **F6** (→V22): `#define PERL_NO_GET_CONTEXT` is placed after `#include "perl.h"` (API.xs:30), so the intended context optimisation never applies. Move it before the perl headers.
- **F7** (→V23): `pwm_set_range` appears twice in `@wpi_perl_functions`. API.pm:42 and 52.
- **F8** (→V23): `lcd_char_def` issues `lcdPuts($fd, "\n")` before defining the char (API.pm:301) — an undocumented side-effect that writes to the display.
- **F9** (→V24): `phys_wpi_map` is a hardcoded 64-entry physical→wiringPi table (API.h:64-99). Likely stale/incorrect for Pi5/RP1; upstream advises against wpi/phys mapping outside 0-63 on RP1.
- **F10** (→V23): ✅ **RESOLVED 2026-06-04 (during V34).** Leftover `interruptHandler()` XS export (API.xs:489-490), superseded by the per-pin generated handlers + dispatcher. **Not a harmless no-op — see F22:** it has no C definition at all, so it is an unresolved symbol. Dead surface to remove. *Removed (XS export + API.h decl) because the dangling symbol broke `make test` under `PERL_DL_NONLAZY` bind-now.*
- **F11** (→B7): XS `bmp180Pressure`/`bmp180Temp` (API.xs:265-271) are pure `analogRead` aliases — duplicated functionality. Exported + documented as raw accessors, so deprecate rather than delete.
- **F12** (→V24): The 40 generated interrupt trampolines + `perl_callbacks[MAX_PINS]` global (API.xs:111-229) are only needed because `wiringPiISR()` has no userdata; `wiringPiISR2()` (V13) makes them obsolete — one generic handler replaces all 40. Two constraints confirmed against `wiringPi.c`: **(a) carry the user's pin (or the SV) via `userdata`, NOT `wfiStatus.pinBCM`.** `pinBCM` is always BCM (wiringPi.c:3015, after `ToBCMPin`), but our callbacks are keyed by the user's pin in their setup scheme — under `setup()` (wiringPi numbering) BCM ≠ user pin, so keying off `pinBCM` fires the wrong callback (only `setup_gpio()`/BCM happens to match — and per V34 those are the only two modes left). **(b) keep the single dispatcher thread + queue.** The generic ISR2 handler runs in wiringPi's per-pin thread and must still only *enqueue*; the lone dispatcher stays the only thread that calls `call_sv`, so exactly one thread ever enters the interpreter (calling Perl directly from N per-pin threads is unsafe). Net: delete the trampolines + `interrupt_handlers[]` table; the per-pin SV store can stay (small) or move into `userdata`. **Implementation tracked in `isr-migration.md` (V4).**

Phase 4 (custom-XS audit — all ⏸ HOLD for live Pi work):

- **F13** (→V26, CRITICAL): `serialGets` heap buffer overflow — the Perl wrapper passes a 0-length `""` (API.pm:111) but the C writes up to `nbytes` into it (API.xs:32-48). Out-of-bounds heap write / memory corruption. Plus `exit(-1)` on read error.
- **F14** (→V27): `spiDataRW` derefs `av_fetch(bytes, i, 0)` with no NULL check (API.xs:80-82) — a sparse/undef element returns NULL → crash.
- **F15** (→V27): `spiDataRW` calls `SvNV(*elem)` twice per element (API.xs:82, 89) — redundant.
- **F16** (→V27): `spiDataRW` runs `dXSARGS` inside a plain C function and the XSUB juggles `PL_markstack_ptr` (API.xs:96-104, 540-549) — fragile/non-idiomatic; should be a straight PPCODE XSUB.
- **F17** (→V28): Interrupt data race — the dispatcher reads `perl_callbacks[pin]`/`SvRV` (API.xs:163-170) unlocked while `setInterrupt` `SvREFCNT_dec`s + replaces it (API.xs:215-217) → potential use-after-free. **Dissolved by the self-pipe redesign (`isr-migration.md`)** — the callback table moves to Perl; no cross-thread SV access.
- **F18** (→V28): Dispatcher and `initThread` call `call_sv` without `G_EVAL` (API.xs:170, 252) — a `die` in the Perl callback croaks inside the worker thread. **Dissolved (`isr-migration.md`)** — callbacks run in the consuming interpreter's own thread under normal `eval`. (The `initThread` half is removed in `threads-patch.md` V1.)
- **F19** (→V29): The dispatcher thread is never shut down or joined (`dispatcher_shutdown` only set to 0; API.xs:130-131, 221-226) and `wiringPiISRStop` is never called → thread/ISR/held-SV leak at teardown. **Dissolved (`isr-migration.md`)** — no dispatcher thread exists; teardown is `wiringPiISRStop` + close pipe.
- **F20** (→V30): `initThread` uses a single global `thread_callback_sv` (one callback only; same race) and a GCC nested function (`PI_THREAD(myThread){...}`, non-standard C) as the thread entry. API.xs:231-259. **Resolved in `threads-patch.md`:** dead `initThread` removed (V1); concurrent Perl via Perl ithreads, not C-spawned threads. The `piThreadCreate2` userdata patch is demoted to that plan's Backlog (C-only workers).
- **F21** (→V31): `physPinToWpi(p)` indexes `phys_wpi_map[64]` with no bounds check (API.xs:261-263) → OOB read for `p<0` or `p>=64`.

Interrupt/ISR cursory review (off-Pi, 2026-06-02) — F22-F25:

- **F22** (interrupt review; refines F10/→V23): ✅ **RESOLVED 2026-06-04 (during V34)** — confirmed exactly as predicted: `make test` runs with `PERL_DL_NONLAZY=1` (bind-now) and the `.so` failed to load (`undefined symbol: interruptHandler`) until the dead export was removed. The exported `interruptHandler()` (XS API.xs:489-490, declared API.h:22) has **no C definition** — only the macro-generated `interruptHandler_0..39` exist (API.xs:178-199). It is an unresolved symbol: with default lazy-bound XS linking the `.so` still builds/loads, but calling the Perl `WiringPi::API::interruptHandler()` sub hits the undefined symbol (and under `--no-undefined`/bind-now the link or load fails outright). So it is not the harmless no-op F10 implied. Removing it (V23) also de-risks the build — watch the V1/V7 link output for an undefined-symbol warning.
- **F23** (interrupt review; minor): Neither `set_interrupt` (API.pm:119-123) nor XS `setInterrupt` (API.xs:204-229) validates `$edge`. `$pin` and `$callback` are checked, but `edge` is passed straight to `wiringPiISR()`, so out-of-range/garbage edge values reach the C layer silently. Add a guard (INT_EDGE_FALLING=1, RISING=2, BOTH=3; SETUP=0 if intended).
- **F24** (interrupt review; fold into V28/V29): `ISR_enqueue_event` silently drops interrupts once the ring buffer is full (`if (event_queue.count < EVENT_QUEUE_SIZE)` with no else branch, API.xs:135-141) — no overflow flag, counter or diagnostic, so bursty interrupts are lost invisibly. Consider an overflow counter exposed to Perl and/or documenting the coalescing/loss semantics.
- **F25** (interrupt review; depends on V13, fold into V29): Re-arming a pin leaks/duplicates the wiringPi listener. `setInterrupt` always ends with `wiringPiISR(pin, edge, handler)` (API.xs:228) and never calls `wiringPiISRStop(pin)` first, so calling `set_interrupt` twice on the same pin re-registers it — in 3.18 this risks a second internal waitForInterrupt thread / stacked registration for that pin. Once V13 lands, call `wiringPiISRStop(pin)` before re-arming. (Minor, same area: the `dispatcher_started` check-then-create at API.xs:221-226 is a TOCTOU if `set_interrupt` is ever called from multiple ithreads, and the global `mine` is overwritten on every call.)

### V24 formal review pass — conclusions (2026-06-04)

V24 split into two unrelated halves; **no new F# raised** — every issue was already
captured and scheduled.

**(a) Interrupt subsystem review.** The substantive review was already done (cursory
pass 2026-06-02 → F22-F25; full thread-safety audit 2026-06-03) and its remediation
roadmap **is `isr-migration.md`** (self-pipe `wiringPiISR2` rewrite). Mapping of every
V24-scoped concern to its scheduled home:

- Dispatcher thread lifecycle / shutdown / join, per-pin callback refcounting, the
  cross-thread `perl_callbacks[]`/`SvRV` race (**F17/F18/F19**) → **dissolved** by the
  self-pipe design (callback table moves to Perl; no dispatcher thread to race or
  join), not "fixed". Documented in isr-migration.md ## Thread-safety audit.
- **F12** — collapse the 40 trampolines + `interrupt_handlers[]` into one generic
  `isr2_writer`, carrying the user-scheme pin via `userdata` (NOT `wfiStatus.pinBCM`),
  single writer per pin → isr-migration.md **V4**. Confirmed against wiringPi.c:
  `pinBCM` is post-`ToBCMPin`, so under `setup()` (wpi numbering) BCM ≠ user pin;
  keying on `userdata` is correct.
- Dead `interruptHandler` (**F10/F22**) → already removed in V34; deletion of the
  remaining `mine`/dispatcher residue → isr-migration.md V4.
- Edge validation (**F23**) → isr-migration.md V2; dropped-event counter (**F24**) →
  isr-migration.md V5; re-arm leak / `wiringPiISRStop`-before-rearm (**F25**) →
  isr-migration.md V4/V6.

All of the above are **gated on V13** (deferred), i.e. on the isr-migration.md run.
V24 schedules nothing new here — the work is already enumerated there.

**(b) F9 — `phys_wpi_map` Pi5/RP1 audit.** Validated on this board (Pi 5 / RP1) by
**V1**'s `t/20-board_map_precheck.t`: all 28 mapped 40-pin-header positions satisfy
`wpi_to_gpio(phys_to_wpi(p)) == phys_to_gpio(p)` against the installed wiringPi 3.18
tables — **no correctness defect found on this hardware**. Residual concern is
maintenance, not correctness: it's a hardcoded table duplicating board data wiringPi
owns, and upstream warns against wpi/phys mapping outside 0-63 on RP1 — but our table
is bounds-limited to the 64-entry physical header and agrees with wiringPi here.
Programmatic replacement stays **B5** (non-blocking); the OOB-read bounds-check on
`physPinToWpi` is already **F21 → V31** (Phase 4). No new F#.

**Net:** V24 logs no F22+ findings; the interrupt fixes live in isr-migration.md
(gated on V13), F9 is validated by V1 with B5/V31 covering the residual.

## Backlog

B1: Wrap the 3.5 five-channel SPI variants (`wiringPiSPIxGetFd/DataRW/SetupMode/Setup/Close`, wiringPiSPI.h:38-42).

B2: Wrap the varargs printf helpers `lcdPrintf` (devLib/lcd.h:43) and `serialPrintf` (wiringSerial.h:32) — likely by formatting on the Perl side and passing a finished string.

B3: Wrap additional device drivers shipped with 3.18 as optional features: mcp23xxx family, pcf8574/pcf8591, sn3218, max31855/max5322, ds18b20, htu21d, rht03, drcSerial/drcNet.

B4: Add Pi-CI unit tests covering the Phase 2 newly wrapped functions (current t/ only covers pin translation + POD).

B5: Replace the hardcoded `phys_wpi_map` with a programmatic mapping (or wrap an upstream equivalent) once F9 is understood.

B6: Decision for V2 — optionally keep `wpiToGpio` / `lcdDefChar` / `lcdPutChar` as working aliases to the correct subs, so existing `:all` / `:wiringPi` imports never break at `use` time and the old names start working instead of dying.

B7: Deprecate the redundant XS `bmp180Pressure`/`bmp180Temp` aliases (F11) — they just call `analogRead`. Point the POD/Perl wrappers at `analog_read` and mark the C aliases deprecated; remove only after a release cycle to avoid breaking consumers that call them for raw values.

B10: Revisit the I2C tests once the standard `/dev/i2c-1` bus is enabled on `rpi1` (currently only `/dev/i2c-13`/`-14` exist, so `wiringPiI2CSetup` aborts on a valid address and the V18/V19 runtime paths can't run here). When enabled: un-skip the acceptance block in `t/70-i2c_fixes.t` (i2c_setup 72/0x48 return an fd) and add a real round-trip for `i2c_read_word` (16-bit) — ideally against a known device, or at least confirm setup succeeds. Also revisit `t/55-i2c_block.t` (currently guards-only) to exercise actual block/raw read/write on a wired device.

B9: Pi5 hard-abort on byte-bank ops (found during V8). On a Raspberry Pi 5, wiringPi's `digitalReadByte`/`digitalReadByte2`/`digitalWriteByte`/`digitalWriteByte2` are unsupported and the C library calls `exit(1)` — so calling any of the new `digital_*_byte` wrappers there kills the consumer's process (can't even be `eval`'d around). Documented as a POD caveat in V8. Consider a defensive guard (e.g. detect Pi5 via `piBoardId`/`piRP1Model` once V11 lands and `croak` instead of letting wiringPi abort). Their runtime test (`t/30-v8_wrappers.t`) is `can()`-only for this reason.

## Explicitly NOT doing

- PiFace support (`wiringPiSetupPiFace*`, wiringPi.h:271-272) — deprecated upstream.
- **softServo** (`softServoWrite`/`softServoSetup`, softServo.h) — declared in the header but **not compiled into `libwiringPi.so.3.18`** (confirmed via `nm` on both libs; dropped upstream as unreliable). Wrapping it would create undefined symbols that fail to load under `PERL_DL_NONLAZY` bind-now (the F22 failure mode). Decided during V16; only softTone is wrapped.
- ~~Removing `setup_sys`/`wiringPiSetupSys` — kept for legacy callers~~ — **reversed 2026-06-02:** only `setup()`/`setup_gpio()` will be supported; `setup_sys`/`wiringPiSetupSys` **and** `setup_phys`/`wiringPiSetupPhys` are now being removed. Tracked as **V34**.
- Wrapping the `gpio` CLI or the `wiringPiD` daemon — out of scope for this binding library.
- ~~Replacing the existing `wiringPiISR` interrupt model with `wiringPiISR2` — ISR2 is added *alongside* (V13), not as a replacement~~ — **refined 2026-06-03:** the *internal* mechanism **does** convert to `wiringPiISR2` (the 40 trampolines collapse to one generic handler, per **F12**) — implementation planned in `isr-migration.md` (its V4). What stays NOT done: removing the *public* `set_interrupt`/`wiringPiISR` surface — the `set_interrupt` signature and behavior remain backward-compatible.
