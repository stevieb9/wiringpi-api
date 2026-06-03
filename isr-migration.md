# Plan: Migrate the interrupt layer to wiringPi 3.18 `wiringPiISR2`

> **NEXT ACTION:** V1 — on the Pi, confirm the installed `<wiringPi.h>` declares `wiringPiISR2` / `wiringPiISRStop` / `struct WPIWfiStatus` and that this Perl is thread-enabled (interrupts segfault on a non-threaded Perl).
> **LAST SESSION:** Plan created from a read of `~/repos/WiringPi` (wiringPi.c ISR2 internals) + current `API.xs`/`API.pm`. Call chain and example section drafted.
> **ARCHIVE:** See isr-migration-archive.md for completed V tasks

## Goal

Convert this module's interrupt subsystem from the legacy `wiringPiISR()`
trampoline design to wiringPi 3.18's `wiringPiISR2()` + `wiringPiISRStop()`,
**keeping the public `set_interrupt($pin, $edge, $callback)` contract intact**
while fixing the latent races, leaks and dead code in the current
implementation. This is the concrete, ISR2-specific realization of the
interrupt findings logged in `UPGRADE-3.18.md` (F12, F17–F19, F22, F23, F25)
and must run **live on a Pi**.

### What changes, in one paragraph

The 40 generated trampolines (`interruptHandler_0..39`), the
`interrupt_handlers[]` function-pointer table and the `MAKE_HANDLER` /
`APPLY_TO_PINS` macros (API.xs:111-202) exist *only* because the old
`wiringPiISR()` callback takes no argument — a per-pin function was the only way
to know which pin fired. `wiringPiISR2()` adds a `void *userdata` parameter and
hands the handler a `struct WPIWfiStatus`, so **one generic handler replaces all
40 trampolines**. The dead no-op `interruptHandler()` export (API.xs:489-490,
unresolved symbol per F22) is deleted in the same pass.

## Relationship to UPGRADE-3.18.md

This is a **focused sub-plan**; `UPGRADE-3.18.md` stays the master. Mapping:

| Here | Master plan item |
|------|------------------|
| V2 (edge validation + constants) | F23 |
| V3 (wrap `wiringPiISRStop`) | part of V13 |
| V4 (generic ISR2 handler, delete trampolines + dead `interruptHandler`, re-arm-safe) | **F12** / V24; F10+F22; F25 |
| V5 (lock `perl_callbacks[]`, `newSVsv`, `G_EVAL`) | F17 / F18 (master V28, Phase 4 ⏸) |
| V6 (teardown: `wiringPiISRStop` + join dispatcher + dec SVs) | F19 (master V29, Phase 4 ⏸) |
| V7 (debounce arg + wrap `waitForInterrupt2`) | part of V13 |
| V9 (downstream RPi::WiringPi interrupt tests) | V33 |

**Note the master's "Explicitly NOT doing" line** ("Replacing the existing
`wiringPiISR` interrupt model with `wiringPiISR2` … added *alongside*, not as a
replacement"). This plan **refines** that: the *internal* mechanism of
`set_interrupt` converts to `wiringPiISR2` (F12 explicitly calls for deleting the
trampolines), while the *public* `set_interrupt` signature and behavior are
preserved — so no consumer breaks. V5/V6 coincide with master **Phase 4
(⏸ HOLD, live-Pi)**; executing this plan *is* that live-Pi work, so treat the
whole plan as Pi-only.

## Background — how `wiringPiISR2` actually works in 3.18

Read from `~/repos/WiringPi/wiringPi/wiringPi.c`. Crucial facts that drive the design:

1. **Signatures** (`wiringPi.h:296-310`):
   ```c
   struct WPIWfiStatus {
       int statusOK;               // -1 error, 0 timeout, 1 irq processed
       unsigned int pinBCM;        // gpio as BCM pin (ALWAYS BCM)
       int edge;                   // INT_EDGE_FALLING (1) or INT_EDGE_RISING (2)
       long long int timeStamp_us; // microseconds
   };
   int wiringPiISR2(int pin, int edgeMode,
                    void (*function)(struct WPIWfiStatus wfiStatus, void *userdata),
                    unsigned long debounce_period_us, void *userdata);
   int wiringPiISRStop(int pin);          // V3.2 — cancels + joins the per-pin thread
   int waitForInterruptClose(int pin);    // legacy alias of wiringPiISRStop
   struct WPIWfiStatus waitForInterrupt2(int pin, int edgeMode, int ms,
                                         unsigned long debounce_period_us);
   ```
   Edge constants (`wiringPi.h:89-92`): `INT_EDGE_SETUP=0`, `FALLING=1`,
   `RISING=2`, `BOTH=3`.

2. **wiringPi owns one thread per armed pin.** `wiringPiISR2` →
   `wiringPiISRInternal` (wiringPi.c:3073) runs `ToBCMPin(&pin)` (converts the
   pin **in place to BCM** per the active `wiringPiMode`), stores
   `isrFunctionsV2[bcm] = fn` and `isrUserdata[bcm] = userdata`, then
   `pthread_create`s an `interruptHandlerV2` thread (wiringPi.c:3114) for that
   pin. So our generic handler is invoked from **N wiringPi-owned threads**, one
   per pin.

3. **The handler runs in wiringPi's thread and gets our `userdata` back
   verbatim.** `interruptHandlerV2` (wiringPi.c:2960) polls the GPIO line, fills
   `wfiStatus` (with `pinBCM = pin`, BCM), and calls
   `isrFunctionsV2[bcm](wfiStatus, isrUserdata[bcm])` (wiringPi.c:3037).

4. **`wfiStatus.pinBCM` is always BCM — never the caller's pin.** Under
   `setup()` (wiringPi numbering) BCM ≠ user pin, so keying our callback table on
   `pinBCM` fires the wrong callback. **Carry the user's pin via `userdata`**
   (F12a). `userdata` round-trips untouched, so passing the caller's own pin
   sidesteps numbering entirely — no translation, works in every setup mode.

5. **Re-arming stacks listeners.** `wiringPiISRInternal` only *warns* if a pin is
   already armed (wiringPi.c:3085) — it does not stop the old thread. So
   `set_interrupt` on an already-armed pin must call `wiringPiISRStop(pin)`
   first (F25).

6. **Calling Perl from N threads is unsafe** — keep our existing **single
   dispatcher thread + event queue**. The generic handler only *enqueues*; the
   lone dispatcher is the only thread that calls `call_sv` (F12b).

## Validation environment

Mirrors `UPGRADE-3.18.md`: **nothing here compiles or runs on the Mac** (no
wiringPi headers, no hardware, threaded-Perl-only). Two tiers:

- **Quick checks** (off-Pi, while editing):
  - XS parse: `perl -MExtUtils::ParseXS=process_file -e 'process_file(filename=>"API.xs",output=>"/tmp/API_check.c")'`
  - Perl syntax: `perl -c -Ilib lib/WiringPi/API.pm`
  - POD: `podchecker lib/WiringPi/API.pm`
- **Full gate** (Pi only): `perl Makefile.PL && make && make test`, plus the
  interrupt exercisers under `valgrind --leak-check=full` and
  `valgrind --tool=helgrind`. Tasks marked **Full gate** are phase exits.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all three:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of isr-migration-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
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

| ID | What | Command | Expected | Actual |
|----|------|---------|----------|--------|
| V1 | **Prereq gate (do first, on the Pi).** Confirm the *installed* `<wiringPi.h>` declares `wiringPiISR2`, `wiringPiISRStop` and `struct WPIWfiStatus` (≥ 3.16), and that this Perl is thread-enabled — `set_interrupt`'s dispatcher uses raw pthreads + `PERL_SET_CONTEXT`, and the POD warns a non-threaded Perl segfaults. If either is missing, stop and record it before touching code. | `grep -n "wiringPiISR2\|wiringPiISRStop\|WPIWfiStatus" $(wpi-config --cflags 2>/dev/null; echo /usr/include/wiringPi.h)` + `perl -V:usethreads -V:useithreads` | both ISR2 symbols + struct present; `usethreads='define'` | ⏳ |
| V2 | **Edge validation + constants (F23).** `set_interrupt`/`setInterrupt` pass `$edge` straight to C unchecked. Add a guard accepting only `INT_EDGE_FALLING(1)`/`RISING(2)`/`BOTH(3)` (reject `SETUP=0` and junk) and expose the four `INT_EDGE_*` constants to Perl so callers stop hardcoding integers. Validate `$pin`, then `$edge`, then `$callback` (in received order). | `perl -c -Ilib lib/WiringPi/API.pm` + XS parse | syntax/XS OK; bad edge croaks; constants importable | ⏳ |
| V3 | **Wrap `wiringPiISRStop(int pin)` (building block).** Add the thin XS wrap + `@wpi_c_functions` export, and a snake_case nothing-fancy Perl pass-through. Needed by V4 (re-arm) and V6 (teardown). Note `waitForInterruptClose` is just a legacy alias — wrap only `wiringPiISRStop`. | XS parse + `perl -c -Ilib lib/WiringPi/API.pm` | XS parses; symbol present; `perl -c` OK | ⏳ |
| V4 | **Core conversion (F12 / F10 / F22 / F25).** Delete the 40 `MAKE_HANDLER` trampolines, `APPLY_TO_PINS`, `interrupt_handlers[]` (API.xs:176-202) and the dead `interruptHandler()` export (API.xs:489-490 + decl in API.h + `@EXPORT_OK`). Add one generic `isr2_trampoline(struct WPIWfiStatus, void *userdata)` that only enqueues `(int)(intptr_t)userdata`. Rewire `setInterrupt` to call `wiringPiISRStop(pin)` first if the pin is already armed (F25), then `wiringPiISR2(pin, edge, isr2_trampoline, 0 /*debounce*/, (void *)(intptr_t)pin)` — **userdata carries the caller's pin, NOT `wfiStatus.pinBCM`** (F12a). Keep the single dispatcher + queue (F12b). Bump `MAX_PINS` 40→64 to match wiringPi's tables (BCM can exceed 40 under `setup_gpio()`). | XS parse + `perl -c` + grep that `interruptHandler_`/`interrupt_handlers`/`MAKE_HANDLER`/`interruptHandler(` are gone | XS parses; no trampoline/dead-symbol residue; `wiringPiISR2` is the only registration call | ⏳ |
| V5 | **Thread-safety (F17 / F18).** Guard `perl_callbacks[]` with a dedicated mutex (separate from `event_mutex`); store callbacks via `newSVsv` (own a private copy) not bare `SvREFCNT_inc`; in the dispatcher take the lock, refcount-pin the SV, unlock, then `call_sv(... G_DISCARD|G_NOARGS|G_EVAL)` and check `ERRSV` so a dying Perl callback can't croak across the worker thread; `SvREFCNT_dec` the pinned SV after. Note the enqueue path runs in wiringPi's cancellable thread — keep it lock+enqueue only (no Perl, no cancellation points). | XS parse + `perl -c` | XS parses; locked read/refcount + G_EVAL in dispatcher | ⏳ |
| V6 | **Lifecycle / teardown (F19).** Today the dispatcher thread is never joined and `wiringPiISRStop` is never called → thread/ISR/SV leak at exit. Add `stop_interrupt($pin)` (call `wiringPiISRStop(pin)`, then lock + `SvREFCNT_dec` + NULL the slot) and `stop_interrupts()` (stop every armed pin, signal `event_cond` with `dispatcher_shutdown=1`, `pthread_join` the dispatcher, reset `dispatcher_started`, free all SVs). Exports + POD. **Public name needs sign-off** — master V29 floated `clear_interrupt`; this plan proposes `stop_interrupt`/`stop_interrupts`. | XS parse + `perl -c` + `podchecker` | parses; teardown subs exported + documented | ⏳ |
| V7 | **Full ISR2 surface (additive, optional but in-scope).** (a) Extend `set_interrupt($pin, $edge, $callback, $debounce_us = 0)` — optional 4th arg threaded into `wiringPiISR2`'s `debounce_period_us`; default 0 keeps the 3-arg call identical. (b) Wrap synchronous `waitForInterrupt2($pin, $edge, $ms, $debounce_us)` returning the `WPIWfiStatus` fields (`statusOK`, `pin_bcm`, `edge`, `timestamp_us`) as a list/hashref. Exports + POD. | XS parse + `perl -c` + `podchecker` | parses; new optional arg + `waitForInterrupt2` wrapper present | ⏳ |
| V8 | **Full gate (Pi).** `perl Makefile.PL && make && make test`. Then targeted exercisers: rising/falling/both fire the right callback under **both** `setup()` (wiringPi numbering, e.g. wpi 0 = BCM 17) and `setup_gpio()` (BCM); re-arm same pin twice (no stacked listener); `stop_interrupt`/`stop_interrupts` cleanly tear down. Run under `valgrind --leak-check=full` and `--tool=helgrind`: no UAF on `perl_callbacks[]`, no leaked threads/SVs/ISR fds, callback `die` contained. Update Changes (bottom of the `3.1801 UNREL` section). | `perl Makefile.PL && make && make test` + valgrind/helgrind exercisers (on Pi) | all green; no leaks/races; correct callback under both numbering modes; Changes updated | ⏳ |
| V9 | **Downstream gate (RPi::WiringPi).** Install the converted module on the Pi; run RPi::WiringPi's interrupt tests `t/200-interrupt_rising_and_pud.t`, `t/201-...falling...`, `t/202-...both...` and `build_testing/build/defacto_interrupt.pl`. Confirm identical externally-observable behavior (rising/falling/both still fire). If consumers should adopt the new teardown subs, note it in that repo. | `cd ~/repos/rpi-wiringpi && prove -Ilib t/200-interrupt_rising_and_pud.t t/201*.t t/202*.t` (on Pi) | interrupt suite green on the wired hardware | ⏳ |

## Call-chain example — `WiringPi::API` (Perl) → `API.xs` (our C) → `wiringPi.c` (upstream)

The illustrative C below is **target/post-migration** sketch code, not the
current source. The worked numbers use `setup()` (**wiringPi numbering**), where
**wiringPi pin 0 = BCM GPIO 17** — the case that proves why `userdata` (not
`wfiStatus.pinBCM`) is the key.

### A. Arming — `set_interrupt(0, 2, \&on_edge)`  (rising edge on wpi pin 0)

**1 — Perl, `lib/WiringPi/API.pm`** (public layer, unchanged signature):

```perl
set_interrupt(0, 2, \&on_edge);     # $pin=0 (wiringPi numbering), $edge=2 (RISING)

sub set_interrupt {
    shift if @_ == 4;                       # drop $self when called as a method
    my ($pin, $edge, $callback, $debounce_us) = @_;
    $debounce_us //= 0;                     # V7: optional, defaults to no debounce
    # V2 guards: $pin, then $edge (1/2/3 only), then $callback (coderef) ...
    setInterrupt($pin, $edge, $callback, $debounce_us);   # -> XS
}
```

**2 — our C, `API.xs`** (`setInterrupt` XSUB). Registers the **one** generic
handler and stashes the *caller's* pin in `userdata`:

```c
int setInterrupt(int pin, int edge, SV *callback, unsigned long debounce_us){
    mine = Perl_get_context();
    if (pin < 0 || pin >= MAX_PINS)          croak("pin out of range\n");
    if (edge < INT_EDGE_FALLING || edge > INT_EDGE_BOTH) croak("edge out of range\n");
    if (!callback || !SvROK(callback) || SvTYPE(SvRV(callback)) != SVt_PVCV)
        croak("callback param must be a CODE reference\n");

    if (perl_callbacks[pin])                 /* re-arm? stop wiringPi's old thread first (F25) */
        wiringPiISRStop(pin);

    pthread_mutex_lock(&callback_mutex);     /* F17 */
    if (perl_callbacks[pin]) SvREFCNT_dec(perl_callbacks[pin]);
    perl_callbacks[pin] = newSVsv(callback); /* own a private copy (F18) */
    pthread_mutex_unlock(&callback_mutex);

    if (!dispatcher_started) {               /* our single Perl-calling thread */
        dispatcher_shutdown = 0;
        if (pthread_create(&dispatcher_thread, NULL, ISR_dispatcher_main, NULL) == 0)
            dispatcher_started = 1;
    }
    /* userdata = the CALLER's pin (0), NOT BCM — round-trips untouched (F12a) */
    return wiringPiISR2(pin, edge, isr2_trampoline, debounce_us, (void *)(intptr_t)pin);
}
```

**3 — upstream C, `wiringPi.c`** (`wiringPiISR2` → `wiringPiISRInternal`,
line 3073). Converts the pin to BCM and spins up the per-pin thread:

```c
wiringPiISR2(0, 2, isr2_trampoline, 0, (void*)0)
  -> wiringPiISRInternal(pin=0, edgeMode=2, fn=isr2_trampoline, NULL, 0, ud=(void*)0)
       ToBCMPin(&pin);                     // wiringPi 0  ->  BCM 17  (in place)
       isrFunctionsV2[17] = isr2_trampoline;
       isrUserdata[17]    = (void*)0;      // our caller-pin, parked under the BCM index
       pthread_create(&isrThreads[17], NULL, interruptHandlerV2, &params);  // line 3114
```

> The numbering split is now explicit: wiringPi keys its tables by **BCM 17**,
> but the value parked there is **our 0**. When the IRQ fires we read back our 0
> and never have to know about 17.

### B. Firing — a rising edge arrives on GPIO 17

**3 — upstream C** (`interruptHandlerV2`, the BCM-17 thread, line 2960):

```c
// edge detected on the line; build status and call our handler:
wfiStatus.statusOK     = 1;
wfiStatus.pinBCM       = 17;              // ALWAYS BCM (line 3015)
wfiStatus.edge         = INT_EDGE_RISING; // 2
wfiStatus.timeStamp_us = <ns>/1000;
isrFunctionsV2[17](wfiStatus, isrUserdata[17]);   // -> isr2_trampoline(wfiStatus, (void*)0)
```

**2 — our C** (`isr2_trampoline`, running in wiringPi's BCM-17 thread —
enqueue only, never touch Perl here):

```c
static void isr2_trampoline(struct WPIWfiStatus wfiStatus, void *userdata){
    int user_pin = (int)(intptr_t)userdata;   /* == 0, the caller's pin (NOT pinBCM=17) */
    ISR_enqueue_event(user_pin);              /* hand off to the single dispatcher (F12b) */
}
```

**2 — our C** (`ISR_dispatcher_main`, our one Perl-calling thread; V5 form):

```c
while (ISR_dequeue_event(&pin)) {             /* pin == 0 */
    SV *cb = NULL;
    pthread_mutex_lock(&callback_mutex);
    if (pin >= 0 && pin < MAX_PINS && perl_callbacks[pin]
        && SvROK(perl_callbacks[pin]) && SvTYPE(SvRV(perl_callbacks[pin])) == SVt_PVCV)
        cb = SvREFCNT_inc(perl_callbacks[pin]);     /* perl_callbacks[0] — matches! */
    pthread_mutex_unlock(&callback_mutex);
    if (!cb) continue;
    dSP; ENTER; SAVETMPS; PUSHMARK(SP); PUTBACK;
    call_sv(SvRV(cb), G_DISCARD|G_NOARGS|G_EVAL); /* G_EVAL contains a dying callback (F18) */
    FREETMPS; LEAVE;
    SvREFCNT_dec(cb);
}
```

**1 — Perl**: `on_edge()` runs in the interpreter. Had we keyed on
`wfiStatus.pinBCM` (17) instead of `userdata` (0), the lookup would hit empty
`perl_callbacks[17]` and the callback would silently never fire — the F12a trap.

### C. Teardown — `stop_interrupt(0)`

```text
Perl  stop_interrupt(0)
  -> API.xs  stop_interrupt(pin=0):
       wiringPiISRStop(0)            -> wiringPi.c: ToBCMPin 0->17;
                                        pthread_cancel(isrThreads[17]); pthread_join(...);
                                        close(isrFds[17]); isrFunctionsV2[17]=NULL; isrUserdata[17]=NULL;
       lock callback_mutex; SvREFCNT_dec(perl_callbacks[0]); perl_callbacks[0]=NULL; unlock
  (stop_interrupts() additionally: dispatcher_shutdown=1; signal event_cond;
   pthread_join(dispatcher_thread); free every remaining perl_callbacks[].)
```

## Discovery Tracking

_None yet._

## Backlog

B1: Surface `wfiStatus` to the async callback too — optionally pass `(edge, timestamp_us)` into the Perl callback (`call_sv` with args) so handlers can see *which* edge fired and when. Today the queue carries only the pin; would need the queue to carry the status struct. Decide whether the public callback contract should grow args (consumer-facing).

B2: Expose the dropped-interrupt count — `ISR_enqueue_event` silently discards events when the ring buffer is full (F24). Add an overflow counter readable from Perl and/or document the coalescing/loss semantics.

B3: Reconsider the fixed `EVENT_QUEUE_SIZE` (256) and `MAX_PINS` (64) once real burst behavior is observed on hardware.

## Explicitly NOT doing

- **`initThread` / `piThreadCreate` refactor (F20)** — separate concern (generic Perl threads, not ISR); tracked by master V30. Out of scope here.
- **Removing the public `set_interrupt` interface or `wiringPiISR` C export** — only the *internal* mechanism converts to ISR2; the consumer-facing API is preserved (see Relationship note).
- **Removing setup modes to "simplify" ISR2** — `userdata` makes the dispatch mode-agnostic, so mode count is orthogonal; setup-mode removal is master V34's call, not this plan's.
- **`waitForInterrupt` (V1, edge-less legacy)** — upstream disabled it for 3.16 and says use `waitForInterrupt2`; we wrap the V2 form only (V7).
