# Proposal: Corrections & additions to `plans/audit-cleanup.md`

**Status:** RESOLVED (genuine convergence at round 4 of 30) — debate between two AIs, every item
verified against the live tree, the generated C, the system typemap, or an actual test run by **both**
participants. Nothing conceded on say-so.

> **Scope reminder:** This is a *plan-correction* proposal. **No V task was executed** — no code, doc, or
> test was changed. The output is the agreed set of edits to make to `plans/audit-cleanup.md` itself.
> Applying these edits to the plan is left for the author to greenlight.

---

## Objective

Decide whether `plans/audit-cleanup.md` (WiringPi::API Perl/XS repo) is **correct and complete** — every
validation task (V1–V7) and review finding (F1–F10) factually accurate, properly scoped, and actually
verifiable — and produce the corrections/additions needed to make it so. The user's intent: a clean,
trustworthy audit ledger before any task is run. Hard constraint: hand-written source only; `API.c` is a
read-only build artifact; claims must cite real code with line numbers.

## Participants & outcome

| Handle | Self-declared name | Role |
|---|---|---|
| claude | Claude (claude-opus-4-8) | Originator — argued the plan needs corrections not execution; wrote this transcript |
| challenger | Claude Fable 5 (claude-fable-5) | Challenger — stress-tested the findings and the originator's own correction slate |

- **Date:** 2026-06-10
- **Final status:** **RESOLVED.** Two factual errors in the *original plan* (F3's "UB", F10's "inverted
  edge constants") and four factual errors in the originator's *opening correction slate* (test-gating
  count, the "all skips" claim, a wrong env-var remedy, a croak-string citation) all died the same way —
  by evidence.

## Decision — the agreed correction slate for `plans/audit-cleanup.md`

Apply these plan edits (no V task executed):

1. **F3 (ledger, mark in place):** rewrite from "dangling pointer / UB / works by luck of stack timing"
   to: *"`wiringPiVersion` (API.xs:225-235) assigns RETVAL the address of local `char ver[16]`. **Not a
   defect:** the ExtUtils T_PV typemap OUTPUT contract copies via `sv_setpv` before the XSUB returns, so
   the address never reaches Perl (API.c corroborates but regenerates — cite the contract, not the
   artifact). Fragile pattern only."* Mark **⏸ DEFERRED → B9** (per maintenance rule, line 25).

2. **V2:** delete the row from the Validation Table. Create **B9**: *"Rewrite `wiringPiVersion` to the
   in-repo PPCODE idiom — `PPCODE:` + `ST(0)=sv_2mortal(newSVpvf("%d.%d",major,minor)); XSRETURN(1);`,
   drop `OUTPUT: RETVAL` (per `serialGets`, API.xs:741/764-766). Rationale: static-analyzer hygiene +
   idiom consistency — NOT a correctness fix."* The "(or make `ver` static)" alternative is **stricken**
   (adds shared mutable state to fix a non-bug). B9 is the next free number (B1–B8 exist; never renumber).

3. **F10 / V7:** **strike** the "inverted edge constants" premise — README:596's "1 (lowering),
   2 (raising)" *matches* `INT_EDGE_FALLING=1 / INT_EDGE_RISING=2` (`use constant` block API.pm:31ff,
   asserted by t/75:28-30, which runs PASS). V7 **survives** on its real reasons: README omits ~half the
   API (`background_interrupt`, `soft_pwm`, `soft_tone`, `worker`, `pi_lock`, `auto_dispatch` each appear
   **0** times) and still carries the retired pthread-segfault caveat (README:580-581). Rewrite V7's
   Expected column so it does **not** presume the `pod2text` regeneration that V7 explicitly defers to the
   author (otherwise the validation is circular).

4. **V1:** (a) note the `F_GETFL` −1 guard **already exists** in `serialGets` (API.xs:748); (b) reword the
   `serialGets` clause to the one real gap: *"the F_SETFL return (749) is unchecked — lowest severity,
   effectively unreachable (clearing O_NONBLOCK on an fd that just passed F_GETFL has no realistic failure
   mode); harden in one line or waive explicitly"*; (c) fix the wording bug — V1 says "before OR-ing
   O_NONBLOCK … in … serialGets," but `serialGets` **clears** it (`flags & ~O_NONBLOCK`, line 749). F1/F2
   (`ensure_interrupt_pipe`) and F8 (includes) are **unchanged — real defects, sound fixes**. Amend the
   NEXT ACTION banner (line 3) and LAST SESSION to match the reworded V1.

5. **Validation realism (the biggest coverage hole):** V1/V3 Expected must state that `t/75-interrupts.t`
   runs **47 hardware-free tests but mocks the changed XS entry points** (`local *…::_arm_interrupt`,
   `…::wiringPiISRStop` at t/75:65-67 and 149-151), so the passing tests **never execute** the C
   `ensure_interrupt_pipe`/fcntl path V1 edits; only the **7-test hardware block** (t/75:232-234) reaches
   it, and **no test drives F1's fcntl-failure or F4's dead-child path**. The honest bar is "compile-clean
   + no regression, with the gap stated." V4's gate is **`RELEASE_TESTING=1`** (t/pod.t:6-8), **not**
   `PI_BOARD`. With V2 gone, t/25's `skip_all` is moot.

6. **F5 / F8:** unchanged — verified real (F5: XS binds `lcdPutchar` at API.xs:324, so README:543's
   "lcdPutChar" is wrong; dangling sentence + unbalanced backticks confirmed. F8: `errno`/`strerror` via
   transitive includes only). **F6 / F7 (V5 / V6):** independently confirmed accurate by both sides — V5
   and V6 stand as written.

## Major points

**Originator (Claude Opus 4.8):**
- F3 is not UB: the generated XSUB copies the local via `sv_setpv` while it is alive, before `XSRETURN`
  — safe by the typemap contract.
- F10's "inverted edge constants" is false; 1=lowering=falling and 2=raising=rising match the code.
- V1 instructs adding a `serialGets` `F_GETFL` −1 check that already exists; serialGets *clears*, not ORs,
  O_NONBLOCK.
- The suite does not exercise the changed C paths; the runtime fixes' true failure modes are untested.
- Verified the untouched V5/V6 doc findings (F6/F7) — both accurate.

**Challenger (Claude Fable 5):**
- Conceded F3-not-UB and no-inversion **on proof**, then drew blood on the originator's slate: V2's fix
  recipe is itself defective (leaves `OUTPUT: RETVAL` → uninitialized-RETVAL warnings); cite the typemap
  **contract**, not regenerable `API.c` line numbers; the edge-constant citation was a croak *string*.
- Disproved the originator's Claim 4 evidence with a live run: **18** files gate on `PI_BOARD` (not "21 of
  22"), and `t/75` runs **47 PASS** (it mocks, it doesn't skip); the "prepend PI_BOARD=1" remedy is the
  wrong env var for the pod tests (`RELEASE_TESTING`).
- F3 must be demoted out of the Validation Table to Backlog per the plan's own taxonomy (non-defect →
  B#).
- The F_SETFL gap is real (reword, don't drop) — then conceded the originator's "effectively unreachable"
  severity after failing to construct a real failure path.
- Added: V7's `diff`-based validation is circular; the plan's NEXT ACTION banner oversells `serialGets`
  the same way old-V1 did.

## Points of agreement (all evidence-checked by both)

- F3 is **not** undefined behaviour (T_PV typemap copies before return); reclassify + defer to B9; delete
  V2 row.
- F10's "inverted edge constants" is false; strike it; keep V7 on incompleteness + retired pthread caveat.
- V1's `serialGets` clause is muddled: F_GETFL −1 guard already present; only F_SETFL is unchecked
  (lowest severity, effectively unreachable); "OR-ing" wording is wrong (it clears).
- Validation does not exercise the changed C code (t/75 mocks the XS entry points); state the gap; V4's
  gate is `RELEASE_TESTING`, not `PI_BOARD`.
- F1, F2, F4, F5, F8 are real with sound fixes; F6/F7 (V5/V6) confirmed accurate.
- The plan's mark-in-place ledger discipline (line 25) and free-number rule (line 28) make the F3→B9 +
  V2-delete mechanics plan-legal.

## Failures to agree

**None.** The sole remaining nuance — the precise *wording* of F_SETFL severity — was resolved when the
challenger searched for a real failure path (Linux `setfl()` rejects clearing `O_APPEND`, setting
`O_NOATIME`/`O_DIRECT`, or `f_op->check_flags` vetoes — none of which clearing `O_NONBLOCK` on a serial
fd trips) and conceded "effectively unreachable" is correct.

---

## Transcript

Prose condensed; **all code, commands, and line citations reproduced verbatim.**

### Turn 1 — claude (Claude Opus 4.8) — 2026-06-10

Position: the plan is broadly sound on its real findings but ships at least two factually wrong findings,
one redundant scope, and a validation regime that verifies nothing on the target machine. Four claims,
each with code:

**Claim 1 — F3/V2 is a false correctness finding; `wiringPiVersion` is NOT UB.** The plan (line 61) calls
it "a dangling pointer once the XSUB returns (undefined behaviour; 'works' only by luck of stack timing)."
The generated artifact disproves it (`API.c:577-588`):

```c
{
    char *	RETVAL;
    dXSTARG;
        int major;
        int minor;
        char ver[16];
        wiringPiVersion(&major, &minor);
        snprintf(ver, sizeof(ver), "%d.%d", major, minor);
        RETVAL = ver;
    sv_setpv((SV*)TARG, RETVAL);
    ST(0) = TARG;
}
XSRETURN(1);
```

`ver` and the `sv_setpv((SV*)TARG, RETVAL)` reading it are in the **same brace scope**; `sv_setpv` copies
the C string into TARG's own buffer while `ver` is alive, before `XSRETURN`. No dangling pointer reaches
Perl. Conceded: the pattern is fragile and `newSVpvf` is cleaner. Not conceded: an audit calling safe code
"UB that works by luck" is itself a defect — correct the truth value.

**Claim 2 — F10/V7's "inverted edge constants" is false.** Code: `INT_EDGE_FALLING=1, INT_EDGE_RISING=2`.
README:596: "1 (lowering), 2 (raising)." Lowering=falling, raising=rising → identical mapping. Strike the
inversion premise; keep V7 on its other legs.

**Claim 3 — V1 tells you to add a check that already exists.** `serialGets` already guards
`if (flags != -1 && (flags & O_NONBLOCK))` (API.xs:748). The only serialGets finding (F8) is about
includes, not fcntl. The unchecked `F_SETFL` there is benign (→ EAGAIN → graceful croak at 762).

**Claim 4 — validation verifies nothing on this machine.** "21 of 22 t/*.t gate on `$ENV{PI_BOARD}`,"
unset here, so V1/V2/V3's tests skip and pod tests are author-only; "Expected: test passes" is
unreachable. Even with `PI_BOARD=1`, F1/F4's failure modes (full pipe, dead child) are untested.

Challenger: attack Claim 1 — prove F3 really is UB, or the plan is wrong.

### Turn 2 — challenger (Claude Fable 5) — 2026-06-10

Central claim survives; two of four contain the same kind of error the plan is indicted for.

**Claim 1 — conceded on the merits (proved, not on say-so):** read `API.c:569-589` and the system typemap
(`/usr/share/perl/5.40/ExtUtils/typemap`, T_PV OUTPUT ~line 372 = `sv_setpv` = copy). F3's "UB" is false.
But the originator's reword is wrong twice: (1) "safe today / shipped toolchain" + API.c line numbers rot
on the next `make` — cite the **typemap contract**. (2) V2's recipe is defective: the XSUB is `char *`
with `OUTPUT: RETVAL` (API.xs:225-235); injecting `ST(0)=sv_2mortal(newSVpvf(...)); XSRETURN(1);` leaves
xsubpp emitting `sv_setpv((SV*)TARG, RETVAL)` on a never-assigned RETVAL → warnings vs "Compiles clean."
The in-repo idiom is `serialGets` PPCODE (API.xs:741, 764-766). And "(or make `ver` static)" adds shared
mutable state. Further: once F3 is style-grade, **V2 belongs in Backlog**, not the Validation Table
(plan lines 10, 31-32).

**Claim 2 — conceded, with better proof:** `t/75-interrupts.t:28-30` asserts `INT_EDGE_FALLING == 1` and
`INT_EDGE_RISING == 2`; ran it, **47 tests PASS**. Ding: "API.pm:356-357" is a **croak message string**,
not the definition — the constants live in `use constant` at API.pm:31ff.

**Claim 3 — half wrong, remedy overshoots:** the `F_GETFL` −1 guard is redundant (agreed), but the
`F_SETFL` return (749) is genuinely unchecked, and "benign" is wrong: if it fails, the next `read` hits
EAGAIN, `errno != EINTR`, and line 762 croaks "read error: Resource temporarily unavailable" — a death in
the mode this code exists to prevent. Reword, don't drop. Also: V1 says "before OR-ing O_NONBLOCK … in …
serialGets," but serialGets **clears** it (`flags & ~O_NONBLOCK`, 749).

**Claim 4 — evidence false:** 22 files, **18** mention `PI_BOARD`; `manifest.t`/`pod.t`/`pod-coverage.t`
gate on **RELEASE_TESTING** (t/pod.t:6-8); `80-phys_to_wpi_bounds.t` has no gate. `prove -lb
t/75-interrupts.t` with PI_BOARD unset → **"Files=1, Tests=47 … Result: PASS"** — only a 7-test SKIP block
is hardware-gated (t/75:232-234). What survives: t/25 does `skip_all` without PI_BOARD (t/25:11-14); and
t/75's hardware-free blocks **mock `_arm_interrupt`/`wiringPiISRStop`** (t/75:66-67), so the 47 tests route
*around* the C code V1 changes. Addition: **V7's validation is circular** — the `diff <(pod2text …) README`
Expected only validates if the fix *is* pod2text regeneration, which V7 defers to the author.

### Turn 3 — claude (Claude Opus 4.8) — 2026-06-10

Re-ran and re-read every assertion on this machine before conceding.

Conceded with own verification: Claim 4 evidence false — `grep -l PI_BOARD t/*.t | wc -l` = **18**;
`env -u PI_BOARD prove -lb t/75-interrupts.t` → **Files=1, Tests=47, Result: PASS**; t/75:65-67 / 150-152
do `local *WiringPi::API::_arm_interrupt = sub { 0 }` / `…wiringPiISRStop = sub { 0 }` — mocks the exact
XS entry points V1 edits. V2 recipe defective (OUTPUT: RETVAL at API.xs:234). Cite the typemap contract,
not API.c. `INT_EDGE_*` defined at `use constant {` API.pm:31; my 356-357 was a croak string. serialGets
*clears* O_NONBLOCK (749). V7 validation circular.

Open dispute (a) V2→Backlog: **conceded** on the plan's taxonomy (line 32). Mechanics: rewrite F3 in the
ledger (mark-in-place, line 25) to "not a defect, T_PV copy contract," mark **⏸ DEFERRED → B9**; delete
the V2 row; new **B9** = rewrite to PPCODE idiom, rationale static-analyzer hygiene + idiom consistency.

Open dispute (b) F_SETFL severity: **hold a sliver.** Reword-not-drop agreed, but "the failure mode this
code exists to prevent" oversells reachability — `F_SETFL` runs only after `F_GETFL` returned
`flags != -1` (fd valid/open); clearing O_NONBLOCK on an already-validated fd has no real failure path
(EBADF excluded; EINVAL/EPERM N/A). Honest severity: "unchecked, lowest severity, effectively
unreachable."

Addition (verified V5/V6): F7 accurate — `setInterrupt`/`initThread` appear **0 times** in API.xs yet
`docs/missing-functions.md:25-26` claims them as wrappers. F6 accurate — `docs/interrupt-examples.md:3`
banners "implemented and shipping" while 753-754 say "API unimplemented … old dispatcher-thread design."

Last open question: prove a path on which `F_SETFL` clearing O_NONBLOCK fails after `F_GETFL` succeeded —
else accept "effectively unreachable" and we're RESOLVED.

### Turn 4 — challenger (Claude Fable 5) — 2026-06-10

Verified the originator's Turn-3 assertions (including the favorable ones): F6, F7 (also: missing-functions
line 226 lists `wiringPiVersion` as *missing* while API.xs:225 wraps it), and t/75:149-151 mocks all hold.

**F_SETFL reachability — conceded properly:** Linux `setfl()` rejects (a) clearing `O_APPEND` on an
append-only file, (b) setting `O_NOATIME` without ownership, (c) setting `O_DIRECT` where unsupported, (d)
`f_op->check_flags` vetoes (tty drivers don't implement). Clearing `O_NONBLOCK` on a serial fd trips none.
The only constructible path is a cross-thread `close()` between 747 and 749 (EBADF race) — contrived, and
the next `read` then fails EBADF with an *accurate* "Bad file descriptor" croak. Agreed final text: *"F_GETFL
−1 guard already present (API.xs:748); the F_SETFL return (749) is unchecked — lowest severity, effectively
unreachable; harden in one line or waive explicitly."*

Footnote: amend the plan's NEXT ACTION banner (line 3) — it oversells serialGets the same way old-V1 did.
B9 mechanics confirmed plan-legal (B1–B8 exist; line 28 never-renumber; line 25 mark-in-place; deleting
the never-executed V2 row leaves no orphan since the ledger carries the pointer).

**RESOLVED** at round 4 of 30 — genuine convergence, not clock pressure. The agreed slate (above as the
Decision) is the text to carry into the writeup. The two original-plan errors (F3 "UB", F10 "inverted")
and the four opening-slate errors (test count, "skips," env-var remedy, croak-string citation) all died by
evidence.
