# Plan: Code & documentation audit — correctness, efficiency, doc accuracy

> **NEXT ACTION:** V1 — `ensure_interrupt_pipe()` fcntl error handling + explicit `errno`/`string` includes in `API.xs`; `serialGets` needs includes only (its F_GETFL −1 guard already exists)
> **LAST SESSION:** 2026-06-10 — plan-correction pass (2-AI debate, RESOLVED; see proposal/audit-cleanup-plan-corrections.md). Corrected F3/F10 findings, demoted V2→B9, reworded V1, fixed V1/V3/V7 validation. No code changed.
> **ARCHIVE:** See audit-cleanup-archive.md for completed V tasks

## Scope & ground rules

- Audited hand-written source only: `API.xs`, `API.h`, `lib/WiringPi/API.pm`, the four `lib/WiringPi/API/*.pm`, the two `*.pod`, `README`, and `docs/*.md`. **`API.c`/`API.o`/`API.bs` are xsubpp build artifacts (not git-tracked) — never edit them.**
- "Conforms to author intent": prefer the smallest correct fix. Behaviour changes that look intentional (documented design choices) are filed under Backlog or "Explicitly NOT doing" for the author to decide, not silently changed.
- **Per-task bookkeeping (user preference, see memory):** as part of *each* V task, (1) add a `Changes` entry at the bottom of the current section, and (2) end the task by proposing a concise commit message (≤72 chars, no AI attribution). Never run `git commit`.
- Validation runs on this Pi: `perl Makefile.PL && make` compiles the XS; `prove -lb t/` runs the suite. Hardware-dependent tests may skip — a clean compile + no new failures is the bar.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all three:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of audit-cleanup-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
  3. **Delete the V# row from this file's Validation Table.**
- V task ❌: update Actual with `❌ YYYY-MM-DD attempt N: reason`. Rerun same V# with attempt N+1. Do NOT create a new V#.
- **Sync review findings** — when a V task (or a Fix) resolves a review finding, mark its `F#` entry in `## Review Findings` **in place**: prefix `✅ RESOLVED (V#)` (or `✅ VALIDATED (V#)` if no code change was needed, or `⏸ DEFERRED → B#` if punted to backlog). Findings are a permanent audit ledger — mark in place; never archive, delete, or renumber them.
- Update ARCHIVE pointer to reflect what's archived (e.g., `V1-V2` → `V1-V3`)
- Update NEXT ACTION to next ⏳ row; update LAST SESSION
- Never renumber within a series. New items get next free number.
- **Discovery triage during V# work** — when you find something while working a V task, classify before continuing:
  - Blocks the current V task → add `Fix N: problem discovered during V# — [what + fix]` to `## Discovery Tracking`; resolve as part of this V task's work.
  - Real bug but doesn't block this V task → add a new V# row (next free) to the Validation Table with ⏳; do not detour to fix it now.
  - Non-blocking improvement → add new B# to `## Backlog` (one `B#` per line, each separated by a blank line).
  - Decided not to do → add to `## Explicitly NOT doing` with a one-line justification.
- Move resolved fixes to archive's "Archived Fixes" section; keep only unresolved in main Discovery Tracking
- To promote a backlog item to an active task: assign it the next free V# (e.g., B3 becomes V8) and move to the Validation Table. The B# slot is retired and never reused.

## Validation Table

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V1 | `API.xs`: in `ensure_interrupt_pipe()` (lines ~92-95) check `fcntl(F_GETFL)` for -1 before OR-ing in `O_NONBLOCK` (`flags \| O_NONBLOCK`), and check the `F_SETFL` return; on fcntl failure close both pipe fds, reset to -1, return -1 (F1, F2). Add explicit `#include <errno.h>` and `#include <string.h>` for `serialGets`' `errno`/`strerror` (F8). **`serialGets` fcntl note (do NOT re-add a guard):** the `F_GETFL` -1 guard already exists (API.xs:748: `if (flags != -1 && ...)`); serialGets *clears* O_NONBLOCK (`flags & ~O_NONBLOCK`, 749), it does not OR it in; only the `F_SETFL` return (749) is unchecked — lowest severity, effectively unreachable (clearing O_NONBLOCK on an fd that just passed `F_GETFL` has no realistic failure mode) — harden in one line or waive explicitly. Resolves F1, F2, F8. | `perl Makefile.PL && make 2>&1 \| grep -i 'error\|warning'`; `prove -lb t/75-interrupts.t` | Compiles clean. **Validation reaches the happy path only:** t/75 runs 47 hardware-free tests but mocks the changed XS entry points (`local *…::_arm_interrupt`/`…::wiringPiISRStop`, t/75:65-67,149-151), so the passing tests never execute the C `ensure_interrupt_pipe`/fcntl path; only the 7-test hardware block (t/75:232-234, `PI_BOARD`-gated) reaches it, and no test drives F1's fcntl-failure path. Bar = compile-clean + no regression, gap noted. | ⏳ |
| V3 | `BackgroundInterrupts.pm`: `arm()`/`disarm()` ignore `syswrite` failure — a dead child raises `SIGPIPE` (process death) or silent loss. Localize `$SIG{PIPE}='IGNORE'`, check the `syswrite` return, refresh liveness via `running()` before writing. Resolves F4. | `perl -c -Ilib lib/WiringPi/API/BackgroundInterrupts.pm`; `prove -lb t/75-interrupts.t` | Compiles; suite stays green. **No existing test drives F4's dead-child path** (t/75's hardware-free blocks mock the XS interrupt entry points; the dead-child write is not exercised). Bar = compile-clean + no regression; the SIGPIPE/dead-child behaviour is unvalidated by the suite — verify by hand or add a targeted test. | ⏳ |
| V4 | POD/markdown fixes in all three copies (`lib/WiringPi/API.pm` POD, `docs/pod.md`, `README`): (a) `lcd_char_def` dangling sentence "...This function is" (API.pm:2958, pod.md:1308); (b) unbalanced backticks `` `0b11111` or 0b00011111` `` (API.pm:2982, pod.md:1332, README:534); (c) `lcdPutChar`→`lcdPutchar` name (README:541); (d) `pwm_set_range` "0 and 1023" wording (range vs duty). Resolves F5, F9. | `podchecker lib/WiringPi/API.pm`; `RELEASE_TESTING=1 prove -lb t/pod.t t/pod-coverage.t` | podchecker clean; pod tests pass. **Note:** `t/pod.t`/`t/pod-coverage.t` are author tests gated on `RELEASE_TESTING` (t/pod.t:6-8) — without `RELEASE_TESTING=1` they `skip_all` and verify nothing; the command sets it. | ⏳ |
| V5 | `docs/interrupt-examples.md`: remove/rewrite the stale "What changed vs isr-examples.md" appendix (lines ~745-790) that still claims "API unimplemented; API.xs still ships the old dispatcher-thread design" and flags items "provisional" — contradicts the shipped self-pipe implementation and the file's own "implemented and shipping" banner. Resolves F6. | `grep -n 'provisional\|unimplemented\|dispatcher-thread' docs/interrupt-examples.md` | No stale "unimplemented/provisional" claims remain | ⏳ |
| V6 | `docs/missing-functions.md`: regenerate (or annotate as stale + correct) against current `API.xs`. Drop the false "wrapped under different XS names" entries `setInterrupt`/`initThread` (neither exists); remove now-wrapped functions wrongly listed as missing (`wiringPiVersion`, `wiringPiISR2`, `wiringPiISRStop`, the I2C raw/block + SPI + RP1 calls); refresh the 62/121 counts and the "Generated:" date. Resolves F7. | `grep -n 'setInterrupt\|initThread' docs/missing-functions.md` | No references to non-existent wrappers; counts match current `API.xs` | ⏳ |
| V7 | `README`: regenerate from the current POD so it stops omitting ~half the API (background_interrupt(s), auto_dispatch_interrupts, worker, soft_pwm_*, soft_tone_*, timing, pi_lock, pad/tone/clock, board identity, I2C block helpers) and stops carrying the retired pthread-segfault caveat (README:580-581). **Edge values are NOT wrong:** README:596 "1 (lowering), 2 (raising)" matches code `INT_EDGE_FALLING=1`/`INT_EDGE_RISING=2` (`use constant` block API.pm:31ff; "lowering"=falling, "raising"=rising) — non-idiomatic wording only, no inversion; a POD-regen would replace the wording incidentally, but it is not a correctness fix. First decide WITH THE AUTHOR whether README becomes `pod2text lib/WiringPi/API.pm > README`; the Expected below depends on that choice. Resolves F10. | If author chooses pod2text regen: `diff <(pod2text lib/WiringPi/API.pm) README` is empty. If author chooses hand-edit: visual check that the interrupt/worker/soft_pwm/pi_lock sections now appear and the pthread caveat (580-581) is gone. | README reflects the current exported API; the retired pthread caveat is gone. (Do NOT use a raw `diff` as the gate unless the pod2text-regen decision was made — otherwise the diff is large by design and Expected is undecidable.) | ⏳ |

## Discovery Tracking

_None yet._

## Review Findings

Audit ledger from the 2026-06-10 read-only review (3 agents). Each `F#` is marked in place as its task closes.

**Correctness — C/XS (`API.xs`, `API.h`)**

- **F1** (→V1): `ensure_interrupt_pipe()` does not check `fcntl(F_GETFL)` for -1 before `flags | O_NONBLOCK`, nor the `F_SETFL` return. A silent failure leaves the self-pipe write end blocking, so the wiringPi ISR thread can block in `write()` — the exact failure the non-blocking design avoids. (API.xs:92-95)
- **F2** (→V1): No error path after `pipe()` succeeds in `ensure_interrupt_pipe()`; if the fcntl step is treated as failure (per F1) both fds must be closed and reset to -1 to avoid an fd leak. (API.xs:88-97)
- **F3** ⏸ DEFERRED → B9: `wiringPiVersion` assigns `RETVAL` the address of local `char ver[16]` (API.xs:225-235). **Corrected: NOT a defect.** The ExtUtils `T_PV` typemap OUTPUT contract copies the string via `sv_setpv` *before* the XSUB returns (corroborated in the generated `API.c`, but cite the typemap contract — `API.c` regenerates on `make`), so the local's address never reaches Perl. No UB, no dangling read. Fragile *pattern* only (taking the address of a stack local for a `char *` RETVAL); cosmetic, so demoted from the Validation Table to B9 per the non-defect→Backlog rule.
- **F8** (→V1): `errno`/`strerror` (serialGets) used without a direct `#include <errno.h>`/`<string.h>` — compiles only via transitive `perl.h`. Add explicit includes. (API.xs:759-762)

**Correctness — Perl (`lib/WiringPi/API/*.pm`)**

- **F4** (→V3): `BackgroundInterrupts::arm()/disarm()` ignore `syswrite` return; the `running` guard reads the raw field without reaping, so a write to a just-dead child can raise SIGPIPE or silently lose the command. (BackgroundInterrupts.pm:35,47)

**Documentation accuracy**

- **F5** (→V4): POD formatting glitches replicated across API.pm POD / `docs/pod.md` / `README`: `lcd_char_def` dangling sentence; unbalanced backticks; `README` says `lcdPutChar` vs actual `lcdPutchar`.
- **F6** (→V5): `docs/interrupt-examples.md` appendix self-contradicts the shipped implementation ("API unimplemented", "provisional") while the file's banner says "implemented and shipping".
- **F7** (→V6): `docs/missing-functions.md` lists many already-wrapped functions as "missing" and references non-existent wrappers `setInterrupt`/`initThread`; the 62/121 summary is untrustworthy.
- **F9** (→V4): `pwm_set_range` docs cite "0 and 1023" — that bound is the duty value, not the range register; the XS takes `unsigned int range` uncapped.
- **F10** (→V7): `README` is a stale render: omits ~half the exported API and keeps the retired "pthreads/segfault" interrupt caveat (README:580-581). **Correction:** the earlier "inverts the edge constants" claim was **false** — README:596 "1 (lowering), 2 (raising)" *matches* `INT_EDGE_FALLING=1`/`INT_EDGE_RISING=2` (lowering=falling, raising=rising; `use constant` block API.pm:31ff). Non-idiomatic wording only; no inversion. V7 stands on the omissions + retired caveat.

## Backlog

B1: `API.xs` `isr2_writer` reads `interrupt_pipe[1]` with no synchronization vs `_close_interrupt_pipe()` (TOCTOU). Mitigated today by caller discipline (Perl stops ISR threads before close). Consider an atomic load or documenting the hard invariant. (API.xs:70-76, 139-142)

B2: `interrupts_dropped` is bumped atomically (`__sync_fetch_and_add`) but reset/read non-atomically — a data race only if an ISR thread is live at reset. Use `__atomic_store_n`/`__atomic_load_n`, or document the "no active writer at close" invariant. (API.xs:75,127,143)

B3: `physPinToWpi(int wpi_pin)` parameter is misnamed — it is semantically a *physical* pin index. Table and bounds check are correct (verified against wiringPi's composed maps). Rename to `phys_pin` across `API.h`/`API.xs`/Perl for clarity. (API.xs:146)

B4: `BackgroundInterrupt`/`Worker` `read()`/`value()` assume the whole length-framed record is buffered once `select()` reports readable, then do a blocking `_read_exact`. True only while the payload stays under `PIPE_BUF` (4096B); a larger user return value can block the "non-blocking" drain. Document the limit or switch to non-blocking + partial buffering.

B5: `WorkerThread` inherits `read()`/`fh()` that silently return `undef` (no pipe channel under thread mode), whereas the sibling `BackgroundInterrupts` croaks with a clear message. Override to croak for a consistent contract.

B6: `BackgroundInterrupt::running()` treats `waitpid == -1` (incl. transient `EINTR`) the same as a clean exit. Distinguish `ECHILD` from other errno. (BackgroundInterrupt.pm:48-52)

B7: `digitalReadByte`, `digitalReadByte2`, `digitalWriteByte2` are documented as developer C-name calls but are absent from `@wpi_c_functions` (only the snake_case `:perl` wrappers are exported). Reconcile the export list with the DEVELOPER FUNCTIONS POD, or note that only the Perl wrappers are public.

B8: `WorkerThread::stop()/running()` call `$thread->join` with no `eval`/`is_joinable` guard, and join during global destruction is unsafe with ithreads. Guard the join.

B9 (demoted from V2; resolves the cosmetic side of F3): rewrite `wiringPiVersion` (API.xs:225-235) to the in-repo PPCODE idiom — `PPCODE:` + `ST(0)=sv_2mortal(newSVpvf("%d.%d",major,minor)); XSRETURN(1);`, and drop `OUTPUT: RETVAL` (mirror `serialGets`, API.xs:741/764-766). This removes the take-address-of-local pattern. **Rationale: static-analyzer hygiene + idiom consistency — NOT a correctness fix** (current code is safe; see F3). Do NOT keep `OUTPUT: RETVAL` while injecting `XSRETURN` — xsubpp would emit `sv_setpv((SV*)TARG, RETVAL)` on an unassigned RETVAL (warnings). The "(or make `ver` static)" alternative is rejected (adds shared mutable state to fix a non-bug).

## Explicitly NOT doing

- Editing `API.c`/`API.o`/`API.bs` — generated build artifacts, not source.
- `serialGets` permanently clearing `O_NONBLOCK` on the fd (API.xs:747-749) — the inline comment documents this as a deliberate choice so VMIN/VTIME timeouts work. Leave as-is unless the author wants save/restore (then promote from here).
- Changing the `$VERSION` / release-versioning scheme — out of scope for a correctness/doc audit.
