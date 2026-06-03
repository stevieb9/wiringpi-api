# Plan: Upgrade WiringPi::API to wiringPi 3.18

> **NEXT ACTION:** V1 — baseline build against wiringPi 3.18 on the Pi (when home) to see what currently breaks
> **LAST SESSION:** Two decisions captured (no code changed). (1) Enriched F12/V24 with the ISR2 refactor constraints — carry the user's pin via `userdata` not `wfiStatus.pinBCM`, and keep the single dispatcher for interpreter safety. (2) New direction: only `setup()`/`setup_gpio()` supported — `setup_sys`/`setup_phys` to be **removed** (added **V34** in Phase 1, before the V7 gate; flipped the old "NOT doing" note, logged the BREAKING Public API impact). ⚠ V34 breaks RPi::WiringPi (`RPi/WiringPi.pm:52` calls `setup_phys()`) — downstream edit tracked under V33. Phase 4 V26-V32 stays ⏸ HOLD; NEXT ACTION unchanged (V1). Nothing runs on the current machine.
> **ARCHIVE:** See UPGRADE-3.18-archive.md for completed V tasks

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

All work happens on the **Raspberry Pi** at home, with wiringPi 3.18 installed —
**nothing in this plan runs on the current machine** (no wiringPi headers, no
hardware, no compiler for the XS here). Two tiers of check, both on the Pi:

- **Quick checks** (fast iteration while editing, before a full build):
  - Perl syntax: `perl -c -Ilib lib/WiringPi/API.pm` (the `XSLoader::load` is a
    runtime statement, so `-c` does not need the compiled `.so`).
  - POD: `podchecker lib/WiringPi/API.pm` and `prove -Ilib t/pod.t`.
  - XS parse (catches XS/typemap syntax errors before compiling):
    `perl -MExtUtils::ParseXS=process_file -e 'process_file(filename=>"API.xs", output=>"/tmp/API_check.c")'`
- **Full gate** (phase exit): `perl Makefile.PL && make && make test` — the real
  compile, link and test against wiringPi 3.18 and any attached hardware. Tasks
  marked **Full gate** are the phase exit criteria.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all three:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of UPGRADE-3.18-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
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

### Phase 1 — Compatibility (make existing wraps work on 3.18)

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V1 | Baseline build against 3.18 on the Pi — see exactly what currently compiles, links or fails, and capture the errors as the concrete Phase 1 worklist; explicitly scan the link/load output for an undefined `interruptHandler` symbol (F22) | `perl Makefile.PL && make 2>&1 \| tee /tmp/wpi-baseline.log` | build runs to completion or fails with errors recorded to drive V2-V6 | ⏳ |
| V2 | Fix camelCase export mismatches in `@wpi_c_functions` (API.pm:16-36): `wpiToGpio`→`wpiPinToGpio`, `lcdDefChar`→`lcdCharDef`, `lcdPutChar`→`lcdPutchar`. Every name in the C export list must resolve to a real XS sub in API.xs. ⚠ consumer-facing (see Public API impact) | `perl -c -Ilib lib/WiringPi/API.pm` then for each C-export name grep it in API.xs | syntax OK; every C export found as an XS sub | ⏳ |
| V3 | Implement `wiringPiVersion` (exported at API.pm:28 but **never defined** in XS). 3.18 signature is `void wiringPiVersion(int *major, int *minor)`. **Decided: Option A (string)** — the XS wrapper returns `"3.18"` as a `char *` (`T_PV` copies the buffer, so a stack buf is safe): a CODE block declares local `int major, minor`, calls `wiringPiVersion(&major, &minor)`, `snprintf`s `"%d.%d"` into the buf, sets `RETVAL`. Keeps the exported camelCase `wiringPiVersion()` sane in scalar context. Add a snake_case `wiringpi_version` wrapper to `@wpi_perl_functions` returning the string in scalar context and the `(major, minor)` pair in list context (`wantarray`); `wiringPiVersion` is already in `@wpi_c_functions`. POD documents the return shape and notes it reports the **wiringPi library** version, not the Perl dist `$VERSION` (V6). | `perl -MExtUtils::ParseXS=process_file -e 'process_file(filename=>"API.xs",output=>"/tmp/API_check.c")'` && `perl -c -Ilib lib/WiringPi/API.pm` | XS parses; symbol present; syntax OK | ⏳ |
| V4 | Align XS prototypes with 3.18 headers: `lcdSendCommand` 2nd arg `char`→`unsigned char` (API.xs:408-410 vs devLib/lcd.h:38); verify SPI / I2C / serial / lcd / softPwm / sr595 signatures in API.xs still match `~/repos/wiringPi/**/*.h` exactly | review each XS prototype against its header + `process_file` XS parse | every wrapped signature matches its 3.18 header; XS parses | ⏳ |
| V5 | Makefile.PL: fix stale fallback message "Ensure version 2.36+" (Makefile.PL:31); confirm `LIBS => -lwiringPi -lwiringPiDev -lrt` and `INC` are still correct for 3.18 | `perl -c Makefile.PL` | syntax OK; message references 3.18 | ⏳ |
| V6 | Version/metadata refresh: bump `$VERSION` 2.3617→3.1801 (API.pm:6, consumed by Makefile.PL `VERSION_FROM`); update POD DESCRIPTION "version 2.36+" → 3.18 (API.pm:550-552); refresh copyright year; sweep README for version refs. ⚠ consumer-facing (see Public API impact). **➡ NEXT IS V34, NOT V7** — V34 sits between V6 and V7 (out of numeric sequence) and must run before the V7 gate; on completing V6, set NEXT ACTION to V34. | `perl -c -Ilib lib/WiringPi/API.pm && podchecker lib/WiringPi/API.pm` | OK; no 2.36 references remain | ⏳ |
| V34 | **Remove unsupported setup modes (BREAKING)** — delete the `wiringPiSetupSys`/`wiringPiSetupPhys` XS wraps (API.xs:293-294,299) + the `setup_sys`/`setup_phys` Perl wrappers (API.pm:130-135) + their `@EXPORT_OK`/tag entries + POD; sweep README. Only `setup()`/`setup_gpio()` remain. ⚠ consumer-facing — **breaks RPi::WiringPi** (`RPi/WiringPi.pm:52`); make the downstream edit (drop the `/^p/` phys branch) **alongside V34 — don't wait for V33** (V34 lands in Phase 1 but V33 isn't gated until after V25, so deferring leaves RPi::WiringPi broken across the whole window); still verify it under V33. **Downstream edit now tracked in rpi-wiringpi by `refactor-setup-modes.md` (V1/V4).** Note: the phys *translation* helpers (`phys_to_wpi`/`physPinToWpi`, `physPinToGpio`) are independent of the removed phys *mode* — decide their fate separately (ties to F9/V31). | `perl -c -Ilib lib/WiringPi/API.pm` + grep that each removed name is gone from XS/exports/POD | only `setup`/`setup_gpio` remain; no dangling refs; this module's `t/` still passes | ⏳ |
| V7 | **Full gate** — Phase 1 exit: build, link and run the suite on a Pi with wiringPi 3.18; every previously-wrapped call still works. **Precondition — V34 must already be done:** grep that `setup_sys`/`setup_phys`/`wiringPiSetupSys`/`wiringPiSetupPhys` are absent from API.pm/API.xs/README/POD/exports; if any remain, V34 was skipped — complete V34 (and its downstream RPi::WiringPi edit) before this gate. | `perl Makefile.PL && make && make test` (on Pi) | compiles, links clean, tests pass; no `setup_sys`/`setup_phys` symbols remain (V34 confirmed) | ⏳ |

### Phase 2 — Coverage (wrap 3.18 calls we don't expose yet)

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V8 | Surface XS subs that have no Perl layer: `softPwmCreate/Write/Stop` (API.xs:436-448), `piLock/piUnlock` (API.xs:460-465), `digitalReadByte(/2)`, `digitalWriteByte(/2)` (API.xs:514-526). Add snake_case wrappers + exports + POD. Audit every XS sub against `@wpi_perl_functions` so none is silently unreachable | `perl -c -Ilib lib/WiringPi/API.pm` + grep audit (each XS sub is exported or intentionally internal) | OK; audit shows no orphaned XS subs | ⏳ |
| V9 | Wrap timing/scheduling core (wiringPi.h:320-329): `delay`, `delayMicroseconds`, `millis`, `micros`, `piMicros64`, `piHiPri` — XS + Perl + POD | XS `process_file` parse + `perl -c` | parses; syntax OK | ⏳ |
| V10 | Wrap the four functions flagged "not yet implemented" in API.xs:273-280: `setPadDrive`, `setPadDrivePin`, `pwmToneWrite`, `gpioClockSet`; delete that stale comment block | XS parse + `perl -c` | parses | ⏳ |
| V11 | Wrap board/identity helpers: `piBoardId`, `piBoard40Pin` (V3.7), `piRP1Model` (V3.14), `getPinModeAlt` (V3.5), `wiringPiGlobalMemoryAccess` (V3.3), `wiringPiUserLevelAccess` (wiringPi.h:228-289) | XS parse + `perl -c` | parses | ⏳ |
| V12 | Wrap the new 3.3 setup variants: `wiringPiSetupPinType`, `wiringPiSetupGpioDevice`, `wiringPiGpioDeviceGetFd` (wiringPi.h:235-257); expose `enum WPIPinType` constants | XS parse + `perl -c` | parses | ⏳ |
| V13 | Wrap interrupt additions: `wiringPiISRStop` (V3.2 — needed for clean teardown of our dispatcher), `wiringPiISR2` + `waitForInterrupt2` (V3.16, `struct WPIWfiStatus`) (wiringPi.h:306-310) | XS parse + `perl -c` | parses | ⏳ |
| V14 | Wrap I2C additions (wiringPiI2C.h:34-43): `wiringPiI2CReadBlockData`, `wiringPiI2CRawRead`, `wiringPiI2CWriteBlockData`, `wiringPiI2CRawWrite`; implement `i2c_interface`/`wiringPiI2CSetupInterface` (XS sub exists; Perl wrapper currently just croaks "not available" at API.pm:361-363) | XS parse + `perl -c` | parses; `i2c_interface` no longer croaks | ⏳ |
| V15 | Wrap SPI additions (wiringPiSPI.h:31-35): `wiringPiSPIGetFd`, `wiringPiSPISetupMode`, `wiringPiSPIClose` | XS parse + `perl -c` | parses | ⏳ |
| V16 | Wrap softTone (`softToneCreate/Stop/Write`, softTone.h) and softServo; add `#include`s, exports, POD | XS parse + `perl -c` | parses | ⏳ |
| V17 | **Full gate** — Phase 2 exit: rebuild and smoke-test every newly wrapped call on a Pi | `perl Makefile.PL && make && make test` (on Pi) | compiles; new calls invocable | ⏳ |

### Phase 3 — Quality (bugs & efficiency in Perl + XS)

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V18 | Fix **F1**: `i2c_read_word` calls `wiringPiI2CReadReg8` — must be `wiringPiI2CReadReg16` (API.pm:398). ⚠ consumer-facing: return value changes | `perl -c -Ilib lib/WiringPi/API.pm` | OK; now calls ReadReg16 | ⏳ |
| V19 | Fix **F2**: `i2c_setup` validates `$addr =~ /^\d$/` — accepts only a single digit, so real addresses like 72 (0x48) are rejected (API.pm:353). Accept full integer/hex addresses | `perl -c -Ilib lib/WiringPi/API.pm` | OK; 0x48/72 accepted, junk croaks | ⏳ |
| V20 | Fix **F3**: `shift_reg_setup` range guards use `&&` (never true) instead of `||` (API.pm:333 and 337-338). ⚠ consumer-facing: now croaks on bad input | `perl -c -Ilib lib/WiringPi/API.pm` | OK; out-of-range input now croaks | ⏳ |
| V21 | Fix **F4/F5**: replace `exit()` calls in XS `serialGets` (API.xs:40) and `spiDataRW` (API.xs:85-86) with `croak` — they currently kill the interpreter; drop the VLA `unsigned char buf[num_bytes]` (API.xs:75) | XS `process_file` parse | parses; no `exit(` in those fns | ⏳ |
| V22 | Fix **F6**: `#define PERL_NO_GET_CONTEXT` sits *after* the perl.h include (API.xs:30) so it has no effect; move it above the perl headers | XS `process_file` parse | parses; macro precedes perl.h | ⏳ |
| V23 | Fix **F7/F8/F10**: remove duplicate `pwm_set_range` in `@wpi_perl_functions` (API.pm:42 & 52); review/justify or drop the stray `lcdPuts($fd,"\n")` in `lcd_char_def` (API.pm:301); delete the dead no-op `interruptHandler()` XS export (API.xs:489-490). ⚠ consumer-facing (see Public API impact) | `perl -c` + XS parse | OK | ⏳ |
| V24 | Formal review pass: interrupt subsystem (dispatcher thread lifecycle, per-pin callback refcounting at API.xs:204-229, shutdown path; **F12** — evaluate replacing the 40 trampolines + global callback array with one generic `wiringPiISR2` handler once V13 lands; carry the user-scheme pin via `userdata`, **not** `wfiStatus.pinBCM`, and keep the single dispatcher — see F12) and **F9** — audit the hardcoded `phys_wpi_map` (API.h:64-99) for Pi5/RP1 correctness (wiringPi warns against wpi/phys mapping outside 0-63 on RP1). Log any new findings as F22+ | review (record findings in `## Review Findings`) | findings logged; fixes scheduled as new V#/B# | ⏳ |
| V25 | **Full gate** — Phase 3 exit: final `perl Makefile.PL && make && make test` on a Pi plus targeted hardware sanity; update Changes (bottom of the `3.1801 UNREL` section) | `perl Makefile.PL && make && make test` (on Pi) | all green; Changes updated | ⏳ |

### Phase 4 — Custom-XS behavior audit & hardening (⏸ HOLD — work live on a Pi)

> **On HOLD by request.** This phase audits the hand-written C in API.xs
> (`serialGets`, `spiDataRW`, the interrupt dispatcher/threads, `physPinToWpi`)
> for correctness, leaks, races and intent. It needs a Pi (hardware +
> `valgrind`/`helgrind`) and several items have intent questions best answered
> interactively, so it will be worked **live on the Pi**. The findings and
> recommended changes are documented now (F13–F21); every task below stays
> `⏸ HOLD` and is **skipped by "proceed"** (which only runs the next ⏳ task)
> until the hold is lifted.
>
> **Open intent questions to settle live:**
> - `serialGets` read semantics — block-until-`nbytes` (current) vs read-what's-available vs block-with-timeout; how to report EOF / partial reads (partial string, `undef`, or `croak`); text vs binary payloads.
> - `initThread` — keep the single-callback + GCC-nested-function design, or refactor (F20).
> - Interrupt teardown — the shape of the public stop/clear API (V29).

| ID | What | Command (run on the Pi) | Expected | Actual |
|----|------|-------------------------|----------|--------|
| V26 | **`serialGets` (F13, CRITICAL)** — heap buffer overflow: the Perl wrapper passes a 0-length scalar (`my $buf = ""`, API.pm:111) but the C writes up to `nbytes` into it (API.xs:32-48) → out-of-bounds heap write. Rewrite as a self-allocating XSUB (`Newx`/`Safefree`, return `newSVpvn(buf, n)`); replace `exit(-1)` with `croak`. **Confirm intent live:** read semantics + EOF/partial handling | `valgrind --leak-check=full perl -Iblib/lib -Iblib/arch test/serial_pi.pl` | no OOB write, no leak; agreed semantics | ⏸ HOLD |
| V27 | **`spiDataRW` (F14/F15/F16)** — NULL-check `av_fetch` before deref (sparse/undef element → crash, API.xs:80-82); compute `SvNV(*elem)` once not twice (API.xs:82,89); drop the VLA for `Newx`/`Safefree`; `croak` instead of `exit(1)`; replace the `dXSARGS`-inside-plain-C + `PL_markstack_ptr` juggling (API.xs:96-104, 540-549) with an idiomatic PPCODE XSUB | `valgrind --leak-check=full perl -Iblib/lib -Iblib/arch test/<spi script>` | no crash on sparse/empty aref; no leak | ⏸ HOLD |
| V28 | **Interrupt thread-safety (F17/F18)** — the dispatcher reads `perl_callbacks[pin]`/`SvRV` (API.xs:163-170) with no lock while `setInterrupt` `SvREFCNT_dec`s + replaces it (API.xs:215-217) → use-after-free. Guard `perl_callbacks[]` with a mutex, store via `newSVsv`; wrap dispatcher `call_sv` in `G_EVAL` so a dying callback can't croak across the worker thread | `valgrind --tool=helgrind perl -Iblib/lib -Iblib/arch testing/interrupt.pl` | no UAF/race; callback death contained | ⏸ HOLD |
| V29 | **Interrupt lifecycle/cleanup (F19)** — the dispatcher thread is never shut down or joined (`dispatcher_shutdown` only ever set to 0; no signal/join, API.xs:130-131,221-226) and `wiringPiISRStop` is never called → thread + ISR + held callback SVs leak at teardown. Add a teardown (set shutdown, signal cond, `pthread_join`, `wiringPiISRStop` per pin [V13], `SvREFCNT_dec` callbacks) exposed as `stop_interrupts`/`clear_interrupt` | `valgrind --leak-check=full perl -Iblib/lib -Iblib/arch testing/interrupt.pl` | thread joined; no leaked thread/SV/ISR | ⏸ HOLD |
| V30 | **`initThread` (F20)** — single global `thread_callback_sv` allows only one callback and shares the same replace/read race; `PI_THREAD(myThread){...}` uses a GCC nested function as the thread entry (non-standard C). API.xs:231-259. **Decide live:** document the GCC requirement + single-callback limit, or refactor to pass the callback through the thread arg | review + `make` (watch for warnings) | decision recorded; compiles clean | ⏸ HOLD |
| V31 | **`physPinToWpi` (F21)** — `physPinToWpi(p)` indexes `phys_wpi_map[64]` with no bounds check (API.xs:261-263) → OOB read for `p<0` or `p>=64`. Return -1 (the map's "non-existent" sentinel) for out-of-range and mirror the guard in the Perl `phys_to_wpi` wrapper | `perl -c -Ilib lib/WiringPi/API.pm` + out-of-range unit test | returns -1; no OOB read | ⏸ HOLD |
| V32 | **Full leak/behaviour gate** — build with debug and run every custom-XS path under `valgrind --leak-check=full` (and `helgrind` for the threads) via the testing/ scripts; confirm no leaks, races or UB across serialGets/spiDataRW/interrupts/initThread | `valgrind --leak-check=full --show-leak-kinds=all perl -Iblib/lib -Iblib/arch testing/interrupt.pl` (and sr/thread/serial scripts) | all clean | ⏸ HOLD |

### Cross-repo — Downstream verification (RPi::WiringPi)

| ID | What | Command (run on the Pi) | Expected | Actual |
|----|------|-------------------------|----------|--------|
| V33 | Downstream gate (depends on V25): install the upgraded WiringPi::API on the Pi, then run RPi::WiringPi's `t/` suite plus the targeted exercisers for changed calls (see the **Downstream verification** section). Confirm valid calls behave identically, `shift_reg_setup` now croaks on out-of-range, and `serial_gets` no longer corrupts memory; then bump RPi::WiringPi's `Makefile.PL` prereq 2.3616→3.1801 and commit it **in that repo** | `cd ~/repos/rpi-wiringpi && prove -Ilib t/` (+ build_testing exercisers) | suite green for the wired hardware; behaviors confirmed; downstream prereq bumped | ⏳ |

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

_None yet._

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
- **F10** (→V23): Leftover `interruptHandler()` XS export (API.xs:489-490), superseded by the per-pin generated handlers + dispatcher. **Not a harmless no-op — see F22:** it has no C definition at all, so it is an unresolved symbol. Dead surface to remove.
- **F11** (→B7): XS `bmp180Pressure`/`bmp180Temp` (API.xs:265-271) are pure `analogRead` aliases — duplicated functionality. Exported + documented as raw accessors, so deprecate rather than delete.
- **F12** (→V24): The 40 generated interrupt trampolines + `perl_callbacks[MAX_PINS]` global (API.xs:111-229) are only needed because `wiringPiISR()` has no userdata; `wiringPiISR2()` (V13) makes them obsolete — one generic handler replaces all 40. Two constraints confirmed against `wiringPi.c`: **(a) carry the user's pin (or the SV) via `userdata`, NOT `wfiStatus.pinBCM`.** `pinBCM` is always BCM (wiringPi.c:3015, after `ToBCMPin`), but our callbacks are keyed by the user's pin in their setup scheme — under `setup()` (wiringPi numbering) BCM ≠ user pin, so keying off `pinBCM` fires the wrong callback (only `setup_gpio()`/BCM happens to match — and per V34 those are the only two modes left). **(b) keep the single dispatcher thread + queue.** The generic ISR2 handler runs in wiringPi's per-pin thread and must still only *enqueue*; the lone dispatcher stays the only thread that calls `call_sv`, so exactly one thread ever enters the interpreter (calling Perl directly from N per-pin threads is unsafe). Net: delete the trampolines + `interrupt_handlers[]` table; the per-pin SV store can stay (small) or move into `userdata`.

Phase 4 (custom-XS audit — all ⏸ HOLD for live Pi work):

- **F13** (→V26, CRITICAL): `serialGets` heap buffer overflow — the Perl wrapper passes a 0-length `""` (API.pm:111) but the C writes up to `nbytes` into it (API.xs:32-48). Out-of-bounds heap write / memory corruption. Plus `exit(-1)` on read error.
- **F14** (→V27): `spiDataRW` derefs `av_fetch(bytes, i, 0)` with no NULL check (API.xs:80-82) — a sparse/undef element returns NULL → crash.
- **F15** (→V27): `spiDataRW` calls `SvNV(*elem)` twice per element (API.xs:82, 89) — redundant.
- **F16** (→V27): `spiDataRW` runs `dXSARGS` inside a plain C function and the XSUB juggles `PL_markstack_ptr` (API.xs:96-104, 540-549) — fragile/non-idiomatic; should be a straight PPCODE XSUB.
- **F17** (→V28): Interrupt data race — the dispatcher reads `perl_callbacks[pin]`/`SvRV` (API.xs:163-170) unlocked while `setInterrupt` `SvREFCNT_dec`s + replaces it (API.xs:215-217) → potential use-after-free.
- **F18** (→V28): Dispatcher and `initThread` call `call_sv` without `G_EVAL` (API.xs:170, 252) — a `die` in the Perl callback croaks inside the worker thread.
- **F19** (→V29): The dispatcher thread is never shut down or joined (`dispatcher_shutdown` only set to 0; API.xs:130-131, 221-226) and `wiringPiISRStop` is never called → thread/ISR/held-SV leak at teardown.
- **F20** (→V30): `initThread` uses a single global `thread_callback_sv` (one callback only; same race) and a GCC nested function (`PI_THREAD(myThread){...}`, non-standard C) as the thread entry. API.xs:231-259.
- **F21** (→V31): `physPinToWpi(p)` indexes `phys_wpi_map[64]` with no bounds check (API.xs:261-263) → OOB read for `p<0` or `p>=64`.

Interrupt/ISR cursory review (off-Pi, 2026-06-02) — F22-F25:

- **F22** (interrupt review; refines F10/→V23): The exported `interruptHandler()` (XS API.xs:489-490, declared API.h:22) has **no C definition** — only the macro-generated `interruptHandler_0..39` exist (API.xs:178-199). It is an unresolved symbol: with default lazy-bound XS linking the `.so` still builds/loads, but calling the Perl `WiringPi::API::interruptHandler()` sub hits the undefined symbol (and under `--no-undefined`/bind-now the link or load fails outright). So it is not the harmless no-op F10 implied. Removing it (V23) also de-risks the build — watch the V1/V7 link output for an undefined-symbol warning.
- **F23** (interrupt review; minor): Neither `set_interrupt` (API.pm:119-123) nor XS `setInterrupt` (API.xs:204-229) validates `$edge`. `$pin` and `$callback` are checked, but `edge` is passed straight to `wiringPiISR()`, so out-of-range/garbage edge values reach the C layer silently. Add a guard (INT_EDGE_FALLING=1, RISING=2, BOTH=3; SETUP=0 if intended).
- **F24** (interrupt review; fold into V28/V29): `ISR_enqueue_event` silently drops interrupts once the ring buffer is full (`if (event_queue.count < EVENT_QUEUE_SIZE)` with no else branch, API.xs:135-141) — no overflow flag, counter or diagnostic, so bursty interrupts are lost invisibly. Consider an overflow counter exposed to Perl and/or documenting the coalescing/loss semantics.
- **F25** (interrupt review; depends on V13, fold into V29): Re-arming a pin leaks/duplicates the wiringPi listener. `setInterrupt` always ends with `wiringPiISR(pin, edge, handler)` (API.xs:228) and never calls `wiringPiISRStop(pin)` first, so calling `set_interrupt` twice on the same pin re-registers it — in 3.18 this risks a second internal waitForInterrupt thread / stacked registration for that pin. Once V13 lands, call `wiringPiISRStop(pin)` before re-arming. (Minor, same area: the `dispatcher_started` check-then-create at API.xs:221-226 is a TOCTOU if `set_interrupt` is ever called from multiple ithreads, and the global `mine` is overwritten on every call.)

## Backlog

B1: Wrap the 3.5 five-channel SPI variants (`wiringPiSPIxGetFd/DataRW/SetupMode/Setup/Close`, wiringPiSPI.h:38-42).

B2: Wrap the varargs printf helpers `lcdPrintf` (devLib/lcd.h:43) and `serialPrintf` (wiringSerial.h:32) — likely by formatting on the Perl side and passing a finished string.

B3: Wrap additional device drivers shipped with 3.18 as optional features: mcp23xxx family, pcf8574/pcf8591, sn3218, max31855/max5322, ds18b20, htu21d, rht03, drcSerial/drcNet.

B4: Add Pi-CI unit tests covering the Phase 2 newly wrapped functions (current t/ only covers pin translation + POD).

B5: Replace the hardcoded `phys_wpi_map` with a programmatic mapping (or wrap an upstream equivalent) once F9 is understood.

B6: Decision for V2 — optionally keep `wpiToGpio` / `lcdDefChar` / `lcdPutChar` as working aliases to the correct subs, so existing `:all` / `:wiringPi` imports never break at `use` time and the old names start working instead of dying.

B7: Deprecate the redundant XS `bmp180Pressure`/`bmp180Temp` aliases (F11) — they just call `analogRead`. Point the POD/Perl wrappers at `analog_read` and mark the C aliases deprecated; remove only after a release cycle to avoid breaking consumers that call them for raw values.

## Explicitly NOT doing

- PiFace support (`wiringPiSetupPiFace*`, wiringPi.h:271-272) — deprecated upstream.
- ~~Removing `setup_sys`/`wiringPiSetupSys` — kept for legacy callers~~ — **reversed 2026-06-02:** only `setup()`/`setup_gpio()` will be supported; `setup_sys`/`wiringPiSetupSys` **and** `setup_phys`/`wiringPiSetupPhys` are now being removed. Tracked as **V34**.
- Wrapping the `gpio` CLI or the `wiringPiD` daemon — out of scope for this binding library.
- Replacing the existing `wiringPiISR` interrupt model with `wiringPiISR2` — ISR2 is added *alongside* (V13), not as a replacement, to preserve backward compatibility.
