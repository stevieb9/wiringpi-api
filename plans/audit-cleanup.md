# Plan: Code & documentation audit — correctness, efficiency, doc accuracy

> **NEXT ACTION:** Only B4's deferred real fix remains (see REVISIT below). All V tasks (V1, V3–V7) and backlog B1–B9 are done; B4 is documented + deferred.
> **REVISIT AT END:** B4 — the real non-blocking + partial-buffering drain (option (b)) was deferred; for now only the `PIPE_BUF` limit is documented. All other backlog items are now cleared, so this is the last open piece. Implement the proper drain (make the results/value fhs `O_NONBLOCK`, buffer partial records in `$self` across calls) WITH tests (a >4KB framed return value must not block `read()`/`value()`).
> **LAST SESSION:** 2026-06-10 — V7 ✅ (author chose pod2markdown regen; replaced stale plain-text README with markdown README.md from current POD, restoring the missing interrupt/worker/soft_pwm/soft_tone/timing/pi_lock/board sections and dropping the retired pthread caveat; renamed via git mv + MANIFEST updated; F10 resolved; empty-diff gate passes).
> **ARCHIVE:** See audit-cleanup-archive.md for completed V tasks (V1, V3, V4, V5, V6, V7)

## Scope & ground rules

- Audited hand-written source only: `API.xs`, `API.h`, `lib/WiringPi/API.pm`, the four `lib/WiringPi/API/*.pm`, the two `*.pod`, `README`, and `docs/*.md`. **`API.c`/`API.o`/`API.bs` are xsubpp build artifacts (not git-tracked) — never edit them.**
- "Conforms to author intent": prefer the smallest correct fix. Behaviour changes that look intentional (documented design choices) are filed under Backlog or "Explicitly NOT doing" for the author to decide, not silently changed.
- **Per-task bookkeeping (user preference, see memory):** as part of *each* V task, (1) add a `Changes` entry at the bottom of the current section, and (2) end the task by proposing a concise commit message (≤72 chars, no AI attribution). Never run `git commit`.
- Validation runs on this Pi: `perl Makefile.PL && make` compiles the XS; `prove -lb t/` runs the suite. Hardware-dependent tests may skip — a clean compile + no new failures is the bar.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").
- **Backlog (B#) confirmation gate**: when told to proceed on a B# item, do NOT implement in the same turn. First reply with a *very brief* note — (a) the problem and (b) its impact — then stop and wait for the user's go-ahead before making any change. (A B# promoted to a V# via the next-free-number rule then follows the normal V-task flow.)

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
| _(none)_ | All Validation-Table V tasks complete. | — | — | — |

## Discovery Tracking

_None yet._

## Review Findings

Audit ledger from the 2026-06-10 read-only review (3 agents). Each `F#` is marked in place as its task closes.

**Correctness — C/XS (`API.xs`, `API.h`)**

- **F1** ✅ RESOLVED (V1): `ensure_interrupt_pipe()` does not check `fcntl(F_GETFL)` for -1 before `flags | O_NONBLOCK`, nor the `F_SETFL` return. A silent failure leaves the self-pipe write end blocking, so the wiringPi ISR thread can block in `write()` — the exact failure the non-blocking design avoids. (API.xs:92-95)
- **F2** ✅ RESOLVED (V1): No error path after `pipe()` succeeds in `ensure_interrupt_pipe()`; if the fcntl step is treated as failure (per F1) both fds must be closed and reset to -1 to avoid an fd leak. (API.xs:88-97)
- **F3** ✅ RESOLVED (B9, 2026-06-10): `wiringPiVersion` assigns `RETVAL` the address of local `char ver[16]` (API.xs:225-235). **Corrected: NOT a defect.** The ExtUtils `T_PV` typemap OUTPUT contract copies the string via `sv_setpv` *before* the XSUB returns (corroborated in the generated `API.c`, but cite the typemap contract — `API.c` regenerates on `make`), so the local's address never reaches Perl. No UB, no dangling read. Fragile *pattern* only (taking the address of a stack local for a `char *` RETVAL); cosmetic, so demoted from the Validation Table to B9 per the non-defect→Backlog rule.
- **F8** ✅ RESOLVED (V1): `errno`/`strerror` (serialGets) used without a direct `#include <errno.h>`/`<string.h>` — compiles only via transitive `perl.h`. Add explicit includes. (API.xs:759-762)

**Correctness — Perl (`lib/WiringPi/API/*.pm`)**

- **F4** ✅ RESOLVED (V3): `BackgroundInterrupts::arm()/disarm()` ignore `syswrite` return; the `running` guard reads the raw field without reaping, so a write to a just-dead child can raise SIGPIPE or silently lose the command. (BackgroundInterrupts.pm:35,47)

**Documentation accuracy**

- **F5** ✅ RESOLVED (V4): POD formatting glitches replicated across API.pm POD / `docs/pod.md` / `README`: `lcd_char_def` dangling sentence; unbalanced backticks; `README` says `lcdPutChar` vs actual `lcdPutchar`.
- **F6** ✅ RESOLVED (V5): `docs/interrupt-examples.md` appendix self-contradicts the shipped implementation ("API unimplemented", "provisional") while the file's banner says "implemented and shipping".
- **F7** ✅ RESOLVED (V6): `docs/missing-functions.md` lists many already-wrapped functions as "missing" and references non-existent wrappers `setInterrupt`/`initThread`; the 62/121 summary is untrustworthy.
- **F9** ✅ RESOLVED (V4): `pwm_set_range` docs cite "0 and 1023" — that bound is the duty value, not the range register; the XS takes `unsigned int range` uncapped.
- **F10** ✅ RESOLVED (V7): `README` is a stale render: omits ~half the exported API and keeps the retired "pthreads/segfault" interrupt caveat (README:580-581). **Correction:** the earlier "inverts the edge constants" claim was **false** — README:596 "1 (lowering), 2 (raising)" *matches* `INT_EDGE_FALLING=1`/`INT_EDGE_RISING=2` (lowering=falling, raising=rising; `use constant` block API.pm:31ff). Non-idiomatic wording only; no inversion. V7 stands on the omissions + retired caveat.

## Backlog

B1: ✅ RESOLVED (doc-only, 2026-06-10): `API.xs` `isr2_writer` reads `interrupt_pipe[1]` with no synchronization vs `_close_interrupt_pipe()` (TOCTOU). Mitigated today by caller discipline (Perl stops ISR threads before close). **Resolution:** documented the stop-before-close lifecycle invariant in the `isr2_writer` comment block, and explicitly warned off an atomic-load "fix" (it does not close the check→write window, so it would imply a thread-safety the code neither needs nor has). No behaviour change; XS recompiles clean. (API.xs:57-71, 151-154)

B2: ✅ RESOLVED (2026-06-10): `interrupts_dropped` is bumped atomically (`__sync_fetch_and_add`) but reset/read non-atomically — a data race only if an ISR thread is live at reset. **Resolution:** chose the genuine fix (not just the invariant doc) since here it is clean — `interrupt_dropped()` now reads via `__atomic_load_n` and `_close_interrupt_pipe()` resets via `__atomic_store_n`, both `__ATOMIC_RELAXED` (standalone counter, no ordering dependency), pairing with the existing atomic increment. Behaviour-equivalent; XS recompiles clean, full suite green (121 tests). (API.xs:86,144-149,161)

B3: ✅ RESOLVED (2026-06-10): `physPinToWpi(int wpi_pin)` parameter is misnamed — it is semantically a *physical* pin index. Table and bounds check are correct (verified against wiringPi's composed maps). **Resolution:** renamed `wpi_pin` → `phys_pin` in the C function body + XSUB (`API.xs:167-174,513-514`) and the prototype (`API.h:34`). Perl side already used neutral `$pin`/`pin`, so no change there. Cosmetic only; XS recompiles clean, `t/80-phys_to_wpi_bounds.t` passes (t/05 needs a Pi board). No Changes entry — internal name, not user-facing.

B4: ⏸ DOCUMENTED + DEFERRED (2026-06-10) — REVISIT AT END: `BackgroundInterrupt`/`Worker` `read()`/`value()` assume the whole length-framed record is buffered once `select()` reports readable, then do a blocking `_read_exact`. True only while the payload stays under `PIPE_BUF` (4096B); a larger user return value can block the "non-blocking" drain. **Author chose option (a) for now:** documented the `PIPE_BUF` limit — corrected the misleading "won't block" inline comments in `BackgroundInterrupt::read()` and `Worker::value()` (now note the ~4KB limit + a TODO marker, tagged `(B4)`), and added a "Size limit" caveat to the `results`/`shared` POD in `API.pm`, regenerated `README.md` (pod2markdown, empty-diff gate green) and hand-synced `docs/pod.md`. **Still TODO (the real fix, option (b), deferred to revisit at end):** make the results/value fhs `O_NONBLOCK` and accumulate partial records in `$self` across calls so a >`PIPE_BUF` return value can't block the drain — WITH proper tests (a >4KB framed return value must not block `read()`/`value()`). `Changes` entry added for the doc note; add another when the real fix lands.

B5: ✅ RESOLVED (2026-06-10): `WorkerThread` inherits `read()`/`fh()` that silently return `undef` (no pipe channel under thread mode), whereas the sibling `BackgroundInterrupts` croaks with a clear message. **Resolution (author approved contract change — code not yet public):** chose option (b) — `read()`/`fh()` **and** `value()` all croak (via a shared `_no_channel` helper using `goto` so croak blames the caller), since `results`/`shared` are rejected at construction under thread mode, so all three are always misuse; option (a) would have left `value()` returning undef and created a new in-class inconsistency. POD updated: `WorkerThread.pm` DESCRIPTION + a combined `read`/`fh`/`value` METHODS entry, and the `API.pm` worker-handle items (regenerated `README.md`, synced `docs/pod.md`). Tests: `t/85-worker.t` asserts the croak directly on the handle class (no ithread Perl needed — verified here, 125 tests pass) incl. caller-attribution; `t/86-worker_thread.t` is the end-to-end thread-construction test (skips on this non-ithreads build, runs on threaded perls) — added to MANIFEST. `Changes` entry added.

B6: ✅ RESOLVED (2026-06-10): `BackgroundInterrupt::running()` treats `waitpid == -1` (incl. transient `EINTR`) the same as a clean exit. Distinguish `ECHILD` from other errno. **Resolution:** imported `ECHILD` (POSIX) and gated the `-1` branch on `$! == ECHILD`, so only a positive reap or `-1/ECHILD` marks the child gone; any other errno (EINTR) leaves the handle running rather than latching it stopped (which would skip stop()'s reap and leak the child). Added `t/87-running_waitpid.t` — overrides `CORE::GLOBAL::waitpid` in a BEGIN before the module compiles to deterministically drive alive/EINTR/ECHILD/positive-reap/latched cases (the EINTR assertion fails against the old `== -1` logic). XS unaffected; full suite 131 tests pass. `Changes` entry added.

B7: ✅ RESOLVED (2026-06-10): `digitalReadByte`, `digitalReadByte2`, `digitalWriteByte2` are documented as developer C-name calls but are absent from `@wpi_c_functions` (only the snake_case `:perl` wrappers are exported). **Resolution (option (a), author approved — code not public):** the snake_case wrappers are the sole public interface for the byte ops. (1) Removed all four byte-op `=head2` entries from DEVELOPER FUNCTIONS — that section's intro declares it holds only wrapper-less calls, but all four have documented `digital_*_byte` wrappers in the main usage POD. (2) Dropped the lone `digitalWriteByte` from `@wpi_c_functions` so the C-names aren't half-exported (the other three never were; t/30 only uses the `:perl` wrappers, so nothing broke). **Discovery while here:** the DEVELOPER intro's blanket "no Perl wrapper equivalent" was also false for `pinModeAlt` (has `pin_mode_alt`); softened the intro to "most are called by their C name; where a wrapper exists it's recommended (e.g. `pin_mode_alt` for `pinModeAlt`)". Left `pinModeAlt` in DEVELOPER FUNCTIONS deliberately — unlike the byte ops it IS a properly-exported C-name, so it's a legit developer call now cross-referenced to its wrapper. Synced README.md (pod2markdown, gate green) + docs/pod.md (TOC + body + intro). No test added (doc/export cleanup; `:all` imports clean, t/30 covers the wrappers). `Changes` entry added.

B8: ✅ RESOLVED (2026-06-10): `WorkerThread::stop()/running()` call `$thread->join` with no `eval`/`is_joinable` guard, and join during global destruction is unsafe with ithreads. **Resolution:** `running()` now joins only when `is_joinable`, under `eval`; `stop()` joins under `eval` only when `is_joinable`, and during global destruction (`${^GLOBAL_PHASE} eq 'DESTRUCT'`, the path the inherited `DESTROY` reaches for a forgotten worker) **detaches** instead of joining; also guarded the `stop_ref` deref. So a double/self join or a teardown-time reap can no longer die or warn. Extended `t/86-worker_thread.t` with idempotent-stop, `{once}` self-exit reap, and stop-after-exit assertions. **Coverage caveat:** this Pi's Perl has `useithreads=no`, so `t/86` skips here — the thread assertions are verified by construction and run on threaded perls/CI; `WorkerThread.pm` compiles clean and the always-run t/85 contract test is unaffected. `Changes` entry added.

B9: ✅ RESOLVED (2026-06-10; resolves the cosmetic side of F3): rewrite `wiringPiVersion` to the in-repo PPCODE idiom. **Resolution:** replaced the `char * / CODE: / RETVAL = ver / OUTPUT: RETVAL` form (which assigned RETVAL the address of a local `char ver[16]`) with `void / PREINIT: int major,minor / PPCODE: wiringPiVersion(&major,&minor); ST(0)=sv_2mortal(newSVpvf("%d.%d",major,minor)); XSRETURN(1);` — mirrors `serialGets`, builds the SV directly (no intermediate buffer), and drops `OUTPUT: RETVAL` so xsubpp emits no `sv_setpv` on an unassigned RETVAL. Static-analyzer hygiene + idiom consistency only — NOT a correctness fix (F3 established the T_PV typemap copied the string before return, so the old code was safe). XS recompiles clean (no warnings); `wiringPiVersion()` still returns "3.18" (verified directly); full suite 131 pass. No `Changes` entry — internal XS refactor, behaviour-identical and invisible to users.

## Explicitly NOT doing

- Editing `API.c`/`API.o`/`API.bs` — generated build artifacts, not source.
- `serialGets` permanently clearing `O_NONBLOCK` on the fd (API.xs:747-749) — the inline comment documents this as a deliberate choice so VMIN/VTIME timeouts work. Leave as-is unless the author wants save/restore (then promote from here).
- Changing the `$VERSION` / release-versioning scheme — out of scope for a correctness/doc audit.

- `serialGets`' unchecked `F_SETFL` return (API.xs:751) — waived during V1: clearing O_NONBLOCK on an fd that just passed `F_GETFL` has no realistic failure mode, and a failure surfaces anyway (read returns EAGAIN → existing croak path). Not worth a guard.
