# Plan: Migrate interrupts to `wiringPiISR2` via a self-pipe

> **NEXT ACTION:** V8 — **Full gate (Pi)**: `perl Makefile.PL && make && make test`, then on-hardware exercisers — (a) single-threaded: arm, drive real edges, `wait_interrupts` loop dispatches the right callbacks under **both** `setup()` (wpi 0 = BCM 17) and `setup_gpio()`; (b) fork: child arms + loops while main works (true background); re-arm twice (no stacked listener); `stop_interrupt(s)` clean. `valgrind --leak-check=full`: no leaks, no leaked fds. This is the first REAL-hardware run of the whole chain — needs GPIO permissions + a wired edge source. Update Changes.
> **LAST SESSION:** **2026-06-04.** Ran **V7 on `rpi1` — PASS**: rewrote INTERRUPT FUNCTIONS POD for the self-pipe model (all new subs + `INT_EDGE_*` + two worked examples; deleted the stale threaded-Perl/segfault caveat). `set_interrupt` gained the optional 4th `$debounce_us` (default 0, validated, → `_arm_interrupt`); `set_interrupt`/`wait_interrupts` switched to `shift if @_ && ref $_[0]` OO-detection (optional args made `@_==N` ambiguous). Reconciled `EDGE_RISING`→`INT_EDGE_RISING` in this plan's examples (Discovery item closed; `isr-examples-final.md` already correct). Folded in **UPGRADE-3.18 B8** (POD link/whitespace fixes) → `podchecker` now fully clean. Clean build; debounce passthrough verified (function+method); `make test` PASS. Changes updated. Prior: V6 PASS (teardown); V5 PASS (dispatch, interrupts fire e2e); V4 PASS (self-pipe core; completed threads-patch.md V1); V3/V2/V1 PASS. **Changes kept current per-task** (user 2026-06-04); `isr-examples-final.md` awaits commit. **Remaining: V8 (Pi full gate + exercisers), V9 (downstream); B7 (unit tests), B8 (RPi::WiringPi cleanup).** Drain contract for V5/V8: EINTR→retry, other-errno→remove+stop, EOF→remove+stop. `isr-examples-final.md` awaits commit.
> **ARCHIVE:** See isr-migration-archive.md for completed V tasks (V1-V7 archived)

## Goal

Convert interrupts from the legacy `wiringPiISR()` trampoline design to
`wiringPiISR2()`, using a **self-pipe**: the wiringPi-owned ISR thread writes a
small fixed event record to a pipe and never touches Perl; the Perl side reads
the pipe and runs callbacks **in the interpreter that is consuming events**.
Public `set_interrupt($pin, $edge, $callback)` stays, plus additive
`interrupt_fd` / `wait_interrupts` / `dispatch_interrupts` / `stop_interrupt(s)`.

### Why self-pipe (the design decision)

A foreign OS thread cannot safely `call_sv` into a shared Perl interpreter — that
is the root hazard behind the current `mine` + dispatcher design (and the reason
the existing POD warns of a segfault on non-threaded Perl). The fix is to **not
call Perl from the foreign thread at all**: the ISR thread does a raw
`write()` (async-safe, lock-free, atomic for records ≤ `PIPE_BUF`), and Perl
dispatches when *it* services the fd. Consequences:

- Works on **non-threaded Perl** (event-loop / blocking-read style), and supports
  true background handling via `fork` (a dedicated child blocks on the fd — see
  Example). ithread-based concurrency is parked (see `threads-patch.md`).
- The callback table lives in **Perl** (`%_interrupt_cb`), touched only by the
  consuming thread — so the cross-thread SV races (F17/F18) and the dispatcher
  thread + teardown (F19) **cease to exist** rather than being "fixed".
- The kernel pipe is the event queue; no `event_queue`/mutex/cond, no `mine`.

## Thread-safety audit (2026-06-03) — the facts this design rests on

Read from `~/repos/WiringPi/wiringPi/wiringPi.c` (3.18) and our `API.xs`.

**libwiringPi has exactly ONE mutex** — `pinMutex` (wiringPi.c:444), used **only**
around ISR registration (wiringPi.c:3092-3133). Everything else is unlocked.
Concurrency therefore depends on the operation:

| wiringPi call | Concurrent-safe? | Why |
|---|---|---|
| `digitalWrite` | ✅ on distinct pins | write-only SET/CLR registers — `*(gpio+gpioToGPSET/GPCLR[pin]) = 1<<bit` (legacy, wiringPi.c:2398-2401) / RP1 `RIO_SET/CLR` offsets (2389-2396). No read-modify-write; unset bits ignored, so writes can't clobber each other. |
| `digitalRead` | ✅ | pure register read — `gpioToGPLEV` / RP1 status (2302-2313). |
| pin-maps & mmap ptrs (`pinToGpio`, `gpio`, `rio`…) | ✅ read | set once at setup, read-only after. |
| `pinMode` | ❌ | read-modify-write on GPFSEL — `*(gpio+fSel) = (*(gpio+fSel) & ~(7<<shift)) | …` (2026/2043); also mutates softPwm/softTone globals (2009-2010). |
| `pullUpDnControl`, `pwmSet*`, `pwmWrite` config | ❌ | RMW on shared config registers. |
| `wiringPiSetup*` | ❌ (once only) | sets process-global `wiringPiMode`, mmap, model detection. |
| device `*Setup` (i2c/spi/adc) | ❌ (once only) | prepend to the **unguarded** global `wiringPiNodes` list (wiringPi.c:98). After built, `wiringPiFindNode` traversal is read-only → concurrent reads safe. |

**Verdict — libwiringPi is concurrency-usable under a contract** (applies to
`fork` *and* ithreads): do all `setup()`, `pinMode`, pull/PWM config and device
`*Setup` **in the main thread/process, once, before spawning**; afterwards spawned
contexts may freely `digitalRead`/`digitalWrite` (ideally each owning distinct
pins); serialize any post-spawn config change. (ithread specifics tracked in
`threads-patch.md`, parked.)

**Our `API.xs`:** the only concurrency-hostile state is the interpreter-bound
interrupt/thread globals — `mine`, `perl_callbacks[40]`, `event_queue`+mutex+cond,
the dispatcher thread, `thread_callback_sv`, the 40 trampolines. **The self-pipe
redesign deletes all of them.** What survives is the pipe fds (process-global
ints) — inherently safe (one pipe per process; any reader works; each
event record ≤ `PIPE_BUF` so concurrent writes from wiringPi's per-pin threads
stay intact). So there is no separate "add locks to API.xs" task — the hostile
state simply goes away.

## Relationship to UPGRADE-3.18.md

| Here | Master plan item |
|------|------------------|
| V2 (edge validation + constants) | F23 |
| V3 (wrap `wiringPiISRStop`) | part of V13 |
| V4 (self-pipe ISR2 writer; delete trampolines + dead `interruptHandler` + `mine`/dispatcher) | **F12** / V24; F10+F22 |
| F17 / F18 / F19 | **dissolved** by the self-pipe design (no cross-thread SV table, no dispatcher thread) — see audit |
| V5 dropped-event counter | F24 |
| V9 (downstream RPi::WiringPi interrupt tests) | V33 |

## Validation environment

**Pi-only** for anything that builds or runs (no wiringPi headers/hardware/compiler
on the Mac). Off-Pi: parse/syntax only.

- **Quick checks** (off-Pi): `perl -MExtUtils::ParseXS=process_file -e 'process_file(filename=>"API.xs",output=>"/tmp/API_check.c")'`; `perl -c -Ilib lib/WiringPi/API.pm`; `podchecker lib/WiringPi/API.pm`.
- **Full gate** (Pi): `perl Makefile.PL && make && make test`, plus single-threaded **and** `fork`-based interrupt exercisers under `valgrind --leak-check=full`.

## Execution rules

- **One task per turn**: when told to proceed or continue (or "next", "go", etc.), perform only the next ⏳ V task listed, then stop and wait for further instruction. Do NOT batch multiple V tasks per turn unless the user explicitly authorizes a batch (e.g., "do V1-V3", "do all the style fixes").

## Maintenance rules

- V task ✅: do all four:
  1. Set Actual to `✅ YYYY-MM-DD attempt N: PASS`.
  2. Append a new bullet at the bottom of isr-migration-archive.md's "Archived V Tasks" section: `- V#: description — ✅ YYYY-MM-DD attempt N: PASS`. One bullet per entry — never run two entries together.
  3. **Delete the V# row from this file's Validation Table.**
  4. **Add a Changes entry** at the bottom of the `3.1801 UNREL` section for any consumer-visible change (new/changed/removed function, export, behaviour). Keep Changes current per-task — do NOT defer to V8 (user 2026-06-04). Skip only for purely internal no-ops; note why in the archive bullet. V8 just does a final sweep.
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
| V8 | **Full gate (Pi).** `perl Makefile.PL && make && make test`. Exercisers: (a) **single-threaded** — arm, drive edges, `wait_interrupts` loop dispatches correct callbacks under **both** `setup()` (wpi 0 = BCM 17) and `setup_gpio()`; (b) **fork** — a child arms + loops `wait_interrupts` while main does other work (proves true background handling); re-arm twice (no stacked listener); `stop_interrupt(s)` clean. `valgrind --leak-check=full`: no leaks, no leaked fds. Update Changes (`3.1801 UNREL`). | `perl Makefile.PL && make && make test` + exercisers (Pi) | green; correct dispatch in both modes + background via fork; no leaks; Changes updated | ⏳ |
| V9 | **Downstream gate (RPi::WiringPi).** Install converted module; run `t/200-interrupt_rising_and_pud.t`, `t/201-…falling…`, `t/202-…both…`, `build_testing/build/defacto_interrupt.pl`. Externally-observable behavior unchanged (rising/falling/both fire). Note new dispatch model if a consumer must call `wait_interrupts`. | `cd ~/repos/rpi-wiringpi && prove -Ilib t/200-interrupt_rising_and_pud.t t/201*.t t/202*.t` (Pi) | interrupt suite green on wired hardware | ⏳ |
| V10 | **`background_interrupt` (hidden fork — additive convenience).** Wrap fork+arm+loop+reap so the user gets background handling in one call: `my $h = background_interrupt($pin, $edge, $cb [, $debounce_us])` forks; the **child** arms the interrupt and runs `$cb` on each edge; returns a handle with `$h->stop` (+ `pid`/`running`). Reap children explicitly by PID via an `END` block — **never** a global `$SIG{CHLD}`. Depends on V4-V6; build/verify with the V8 gate. Full spec in the design section below. | `perl -c` + Pi fork exerciser (handler fires; `stop` reaps; no zombie) | one-call background handler works; child reaped cleanly | ⏳ |
| V11 | **Async auto-dispatch via `SIGIO` (optional).** `auto_dispatch(1)` puts the interrupt fd in async mode (`F_SETOWN`+`O_ASYNC`/`F_SETSIG`) and installs a `$SIG{IO}` handler that drains + dispatches, so `set_interrupt` callbacks fire **automatically in the main interpreter** with no `dispatch_interrupts`/loop. Runs at Perl op boundaries → lock-free shared state; document the long-non-yielding-C deferral and that it claims a process signal (save/restore the prior handler; offer an RT signal via `F_SETSIG`). Depends on V4-V5. | `perl -c` + Pi test (callback fires while main runs a Perl loop and during `sleep`; clean enable/disable) | callbacks fire with no loop; no signal leak | ⏳ |

## Example + code flow — Perl → `API.pm` → `API.xs` → wiringPi `wiringPi.c`

Illustrative C is target/post-rewrite. Worked numbers use `setup()` (wiringPi
numbering) where **wpi pin 0 = BCM 17**, showing why `userdata` (the caller's pin)
is the key, not `wfiStatus.pinBCM`.

### Two ways to consume (your choice of concurrency)

**Single-threaded / event-driven (any Perl):**
```perl
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_RISING);
setup();
pin_mode(0, 0);
set_interrupt(0, INT_EDGE_RISING, sub { my ($edge, $ts) = @_; print "edge=$edge at $ts us\n" });
wait_interrupts(1000) while 1;     # blocks on the fd, dispatches in THIS thread
```

**Background via `fork` (main stays free; no threaded Perl):**
```perl
use IO::Select;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_RISING);

setup();                           # ONCE in main, before forking (audit contract)
pin_mode(0, 0);
pipe(my $rx, my $tx) or die "pipe: $!";

my $pid = fork // die "fork: $!";
if ($pid == 0) {                   # child owns the interrupt; arm HERE
    close $rx;
    set_interrupt(0, INT_EDGE_RISING, sub { my ($e, $ts) = @_; syswrite $tx, "$ts\n" });
    wait_interrupts(1000) while 1; # dispatch here, concurrent with main
    exit 0;
}

close $tx;                         # parent: free to work; drain $rx when it likes
my $sel = IO::Select->new($rx);
while (1) {
    # ... main's own work ...
    while ($sel->can_read(0)) {
        my $n = sysread($rx, my $rec, 64);
        if (!defined $n) {
            last if $!{EINTR};         # signal: retry next pass
            $sel->remove($rx); last;   # other error: stop watching, don't spin
        }
        if ($n == 0) { $sel->remove($rx); last }   # EOF: child gone — stop watching
        print "edge reported\n";
    }
}
```
(Canonical, reviewed version of this drain — with text line-framing — is
`isr-examples-final.md`, scenario 9. An ithread-based equivalent — shared vars
instead of a pipe — is in `threads-examples.md`, parked.)

### Arming — `set_interrupt(0, 2, \&cb)`

```text
1 Perl (user)     set_interrupt(0, 2, \&cb);
2 Perl (API.pm)   $_interrupt_cb{0} = \&cb;  _arm_interrupt(0, 2, 0);     # callback stays in Perl
3 API.xs          _arm_interrupt(pin=0,edge=2,deb=0):
                    (lazily create the pipe, write end O_NONBLOCK)
                    wiringPiISR2(0, 2, isr2_writer, 0, (void*)0);          # userdata = caller pin 0
4 wiringPi.c      wiringPiISR2 -> wiringPiISRInternal: ToBCMPin 0->17;
                    isrFunctionsV2[17]=isr2_writer; isrUserdata[17]=(void*)0;
                    pthread_create(&isrThreads[17], …, interruptHandlerV2);
```

### Firing — a rising edge on GPIO 17  (NO Perl on this path)

```text
4 wiringPi.c      interruptHandlerV2 (BCM-17 thread): wfiStatus={pinBCM=17,edge=2,ts};
                    isrFunctionsV2[17](wfiStatus, isrUserdata[17]);        # -> isr2_writer(.., (void*)0)
3 API.xs          isr2_writer(wfiStatus, ud):
                    rec = { .pin=(int)(intptr_t)ud /*=0, the caller pin*/, .edge=2, .ts_us=wfiStatus.timeStamp_us };
                    if (write(pipe_wr, &rec, sizeof rec) < 0 && errno==EAGAIN) dropped++;
                    # returns immediately; interpreter never touched
```

### Dispatch — when Perl services the fd (main thread, or the fork child above)

```text
2 Perl (API.pm)   wait_interrupts($ms): select(interrupt_fd) -> dispatch_interrupts():
                    while (sysread interrupt_fd, $buf, 16) { ($pin,$edge,$ts)=unpack"i i q",$buf;
                                                              $_interrupt_cb{$pin}->($edge,$ts); }   # $pin==0 -> matches
1 Perl (user)     &cb runs in the consuming interpreter, in normal context (G_EVAL-able).
```
Keying on `userdata` (0) — not `pinBCM` (17) — is what makes `$_interrupt_cb{0}`
match under `setup()`; under `setup_gpio()` they'd coincide.

## Design — `background_interrupt` (hidden fork, optional convenience)

Goal: independent background interrupt handling with **one call and a callback** —
the library owns the fork, the wait loop, and the cleanup. Convenience layer over
`isr-examples.md` scenario 8 (manual fork), which stays as the under-the-hood
reference. Pure ISR + `fork`; no threads.

### Public API (provisional names)

    my $h = background_interrupt($pin, $edge, $callback [, $debounce_us]);

    $h->stop;        # stop: signal child, run its ISR teardown, reap it
    $h->pid;         # child PID (diagnostic)
    $h->running;     # true while the child is alive

`$callback` receives `($edge, $timestamp_us)`. `background_interrupt` croaks on a
bad pin/edge/coderef **before** forking.

### The one semantic the user must know

**The callback runs in the forked child, not in main.** It sees a copy-on-write
snapshot of memory as of the call and cannot mutate main's variables — exactly
right for *independent* handlers (drive a pin, log, send a message). Feeding a
value back to main needs an explicit channel (see "Getting data back"); that is
not part of the core call.

### What it does internally

1. Validate args; croak on error (failures surface in the parent, pre-fork).
2. `fork()` (croak on failure).
3. **Child:** install a `SIGTERM` handler that runs `stop_interrupt($pin)` then
   `exit 0`; `set_interrupt($pin, $edge, $callback, $debounce_us)` — arming
   **after** the fork is mandatory (wiringPi ISR pthreads don't survive `fork`);
   then `wait_interrupts($timeout)` forever, running `$callback` directly on each
   edge. No parent-child pipe is needed for fire-and-forget handlers — the only
   pipe is the internal self-pipe inside the child.
4. **Parent:** record the child PID in a small handle object and in a
   module-private list; return the handle.

### Lifecycle & safety

- **`stop`:** `kill 'TERM'` -> poll briefly -> escalate to `kill 'KILL'` ->
  `waitpid`. The child's TERM handler runs `wiringPiISRStop`, releasing the kernel
  ISR and fds.
- **No global signal hijack.** Reap **only our own** children, by PID
  (`waitpid $pid, WNOHANG`). Do **not** set `$SIG{CHLD}='IGNORE'` — that breaks the
  user's own `waitpid`/`system`.
- **`END` block** reaps any still-running background children at exit, so a
  forgotten `stop` can't leak a zombie or orphan a handler.
- **`DESTROY`** stops the child when an owning handle goes out of scope.
- **Croak before fork** on bad input — never fork into a guaranteed failure.

### Caveats to document

- **`fork` inherits open fds** (i2c/spi/serial handles, sockets). Recommend
  calling `background_interrupt` **before** opening other long-lived resources, or
  accept the duplication; the child needs only the inherited GPIO mmap + its own
  self-pipe.
- **Don't use in a program that has spawned ithreads** — `fork` + threads is
  unsafe (not a concern on the ISR track).
- **`setup()` + `pin_mode` run in the parent first** (audit contract); the child
  inherits the configured state.

### Getting data back (optional, not core)

For independent handlers, nothing is needed. If a handler must report to main, add
(opt-in, later): a shared-memory scalar the handle exposes (`$h->shared`), or a
results pipe the parent drains (the scenario 8 pattern). Keep this out of the
default call so the common case stays a one-liner. (Backlog B5.)

### Multiplicity

v1: one child per `background_interrupt` call (simple, isolated). A single shared
child handling many pins is more efficient but needs a control channel to arm pins
post-fork — defer unless wanted (Backlog B4).

## Design — async auto-dispatch (`SIGIO`, optional)

Goal: the closest safe analog to C's "fires on its own while busy," but with the
callback running in **your own interpreter** touching your own variables — and
**no dispatch loop** to write. Enable once; `set_interrupt` callbacks then fire
automatically.

### Public API (provisional)

    auto_dispatch(1);     # enable: wire the interrupt fd to a signal + install handler
    auto_dispatch(0);     # disable: restore fd flags + the prior signal handler

    set_interrupt($pin, $edge, $cb);   # callbacks now fire on their own

One global switch — nothing per-callback changes. (Could fold into a
`set_interrupt` option later — Backlog B6.)

### How it works

1. Ensure the interrupt self-pipe exists; take its read fd.
2. `fcntl` the read fd: `F_SETOWN => $$` (deliver the signal here) and `O_ASYNC`
   (raise `SIGIO` when readable). Optionally `F_SETSIG` to deliver a dedicated
   real-time signal instead, to avoid clashing with other `SIGIO` users.
3. Install `$SIG{IO}` (or the chosen RT signal) = the same drain+dispatch logic as
   `dispatch_interrupts()`.
4. On an edge: wiringPi's C thread writes the record → the kernel signals this
   process → Perl's **safe-signal** machinery runs the handler at the next opcode
   boundary → your callback runs in the main interpreter.

### Why it's safe without locks

Perl safe signals run the handler **between** main's opcodes — never truly in
parallel. The callback has exclusive use of the interpreter while it runs, so it
can read/modify your program's variables with **no mutex and no data race**. That
is the crucial difference from a C thread (genuinely parallel, needs locking).

### When it fires (and when it doesn't)

- **Fires:** during ordinary Perl execution (op boundaries — sub-ms latency), and
  when main is blocked in a signal-interruptible syscall (`sleep`, `select`,
  blocking `read` → `EINTR`).
- **Deferred:** during a long, non-yielding **XS/C** call that never returns to the
  run loop — the callback waits until it returns. (A real thread has no such gap;
  this is the one thing auto-dispatch can't match — use `background_interrupt`
  then.)

### Caveats to document

- **Claims a process signal.** `SIGIO` is process-global; `auto_dispatch` saves and
  restores the prior `$SIG{IO}` on enable/disable, and an RT signal (`F_SETSIG`)
  reduces collisions. Don't enable it if your program already drives
  `SIGIO`/`O_ASYNC`.
- **Keep callbacks short** — they run at an op boundary in the signal handler; a
  slow callback stalls main. Bursts may coalesce into one signal, so the handler
  drains **all** pending records.
- **`O_ASYNC` on a pipe** works on Linux but verify on the Pi; a `socketpair` is a
  reliable fallback for the self-pipe.
- **Process ownership.** Enable in the process that should receive callbacks; if
  you `fork` afterwards, fd-owner/signal settings are inherited — prefer
  `background_interrupt` for the fork model rather than mixing the two.
- **Not true preemption** — see "Deferred," above.

### Relationship to the other modes

Same self-pipe core (V4); auto-dispatch only changes *who pulls the trigger*: the
kernel (a signal) here, your loop in cooperative mode, a forked child in
`background_interrupt`. So: `auto_dispatch` = in-process + shared state + no loop;
`background_interrupt` = separate process, fires even during long C; cooperative
`dispatch_interrupts` = explicit control.

## Discovery Tracking

- ✅ RESOLVED in **V7**: the `EDGE_RISING` vs `INT_EDGE_*` naming mismatch (raised in V2). The design-section examples here now use `INT_EDGE_RISING`; `isr-examples-final.md` already used `INT_EDGE_*`; the POD documents the `INT_EDGE_*` constants. No `EDGE_*` aliases added — `INT_EDGE_*` (wiringPi's own names) is canonical.

## Backlog

B1: Pass the full `wfiStatus` to callbacks optionally — the record already carries edge + timestamp; consider a richer callback signature or a stats accessor.

B2: Coalescing policy — document/expose whether bursts beyond the pipe buffer coalesce; `interrupt_dropped()` already surfaces the count (F24).

B3: Provide a tiny built-in dispatch loop helper (e.g., `run_interrupt_loop()`) for users who don't want to write the `wait_interrupts while 1` themselves.

B4: `background_interrupt` — a single shared background child handling many pins (with a control channel to arm pins post-fork), instead of one child per call.

B5: `background_interrupt` — optional data-back channel (`$h->shared` shared-memory scalar, or a results pipe the parent drains) so a background handler can report a value to the parent.

B6: `auto_dispatch` refinements — per-`set_interrupt` opt-in (vs the global switch), and a configurable delivery signal (default `SIGIO`, or a dedicated RT signal via `F_SETSIG`).

B7: Write unit tests for the interrupt subsystem. Hardware-free coverage: `INT_EDGE_*` constants present/correct (V2), `set_interrupt` edge/pin/callback validation croaks (V2), `interrupt_fd()` returns -1 before arming and a valid fd after (V4/V5), `dispatch_interrupts`/`wait_interrupts` fan a hand-written record (`pack "i i q"`) written directly into the pipe out to the right `%_interrupt_cb` callback without any GPIO (lets the drain contract — EINTR/EOF/errno — be tested off-hardware), `interrupt_dropped()` increments when the pipe is stuffed, and `stop_interrupt(s)` clears state. Plus the on-Pi exercisers already specced in V8/V9 (real edges, fork background, re-arm-no-stack, leak check). Land the hardware-free `t/` file alongside V5/V6 and the wired tests at V8; this B# tracks making it a first-class, repeatable suite (cf. UPGRADE-3.18 B4 Pi-CI coverage).

B8: Determine whether RPi::WiringPi's cleanup path must call `stop_interrupts()` (V6). RPi::WiringPi has a `cleanup`/`DESTROY` that resets pins; once V6 lands, check whether a consumer that armed interrupts via the OO/`set_interrupt` layer leaks the wiringPi ISR thread + the self-pipe fds at teardown if cleanup doesn't also call `stop_interrupts()`. If so, wire `stop_interrupts()` into RPi::WiringPi's cleanup (committed in that repo) and/or document it as the consumer's responsibility. Cross-link to the V9 downstream gate. (The new design has no dispatcher thread to join, but armed pins still hold a wiringPi ISR thread + the pipe until `wiringPiISRStop` + pipe close.)

## Explicitly NOT doing

- **Calling Perl from the wiringPi ISR thread** (the old `mine` + dispatcher model) — the hazard this whole redesign removes; the foreign thread only `write()`s.
- **A C dispatcher thread of our own** — the kernel pipe + the consuming interpreter replace it; no thread to create, race, or join.
- **Requiring threaded Perl** — works everywhere; background handling uses `fork`. ithread-based concurrency is parked (`threads-patch.md` / `threads-examples.md`).
- **`initThread` / general threads / ithreads** — separate concern, **parked**; see `threads-patch.md` and `threads-examples.md`.
