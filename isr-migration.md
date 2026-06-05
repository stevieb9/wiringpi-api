# Plan: Migrate interrupts to `wiringPiISR2` via a self-pipe

> **NEXT ACTION:** **Documentation tasks V18 + V19** (the only pending items). All interrupt *features* are done: upstream wiringpi-api V1-V8 (core), V9 (downstream gate), V10-V11/V13-V17/V20 (background_interrupt[s]+results, auto_dispatch_interrupts incl. configurable signal + set_interrupt opt-in, last_interrupt, interrupt_buffer, run_interrupt_loop/stop, background_interrupts shared child); downstream V12 (fork-safe cleanup + OO wrappers) plus the OO proxies. All PASS on Pi 5 hardware. **V18:** refresh `isr-examples-final.md` + emit `lib/INTERRUPTS.pod` (incl. the code-flow section; omit Status + What-changed). **V19:** create `lib/INTERRUPTS.md` in rpi-wiringpi and rpi-pin (each reflective of its own API; no code-flow section). Remaining loose end: **nothing committed yet — all changes across wiringpi-api, rpi-pin and rpi-wiringpi are in their working trees.** **The backlog (B1-B6) is fully promoted/retired — nothing optional remains.**
> **LAST SESSION:** **2026-06-05.** **V20 PASS** (promoted from B6): `auto_dispatch_interrupts($enable, $signal)` gained a configurable delivery signal (default SIGIO; a named signal like `'USR1'` wired via `F_SETSIG` to avoid clashes), and `set_interrupt(...,{auto_dispatch=>1})` opt-in enables auto-dispatch as part of arming. Fixed an EINVAL (F_SETSIG got the signum as a string → pointer; force `0 + $signum`). `make test` 230 PASS; hardware-verified (USR1 8/8, SIGIO untouched + restored; opt-in 8/8; unknown-signal croak; default SIGIO 8/8). Downstream: `$pi->auto_dispatch_interrupts($bool,$sig)` + `$pin->set_interrupt(...,{auto_dispatch=>...})`. **All backlog (B1-B6) now done; only docs V18/V19 remain.** Earlier same day: **V16 + V17 PASS** (promoted from B4/B5): `background_interrupts([$pin,$edge,$cb,$deb], ...)` — one shared child for many pins, dual-fd (control+interrupt) select loop, handle adds `arm`/`disarm` over a control pipe (callbacks fixed at fork); and `background_interrupt(...,{results=>1})` — opt-in data-back channel shipping the callback's return value to the parent, drained via `$h->read`/`$h->fh`. `make test` 223 PASS; hardware-verified (one child served pins 17+27, disarm/arm toggled, results delivered). Downstream: `$pi->background_interrupts`, and `$pin->background_interrupt` now forwards the options hashref. Remaining: docs-only V18/V19. Earlier same day: **V15 PASS** (`run_interrupt_loop()`/`stop_interrupt_loop()`, promoted from B3): a blocking dispatch loop (`wait_interrupts` in a loop, returns total dispatched; stops on the signal-safe `stop_interrupt_loop()` flag or after `$max`; sleeps when nothing armed to avoid busy-spin); `t/75` coverage (caught + fixed a test-only fake-pipe fd-reuse hang by clearing the cached handle); `make test` 219 PASS; hardware-verified (max-stop → 5, callback-stop → 3). Downstream: `$pi->run_interrupt_loop`/`stop_interrupt_loop`. Earlier same day: **V14 PASS** (`interrupt_buffer()` + overflow policy, promoted from B2): documented the FIFO-queue/drop-and-count (no merge, no block) contract in the `interrupt_dropped()` POD; added `interrupt_buffer([$bytes])` (get/set the self-pipe capacity via `F_GET/SETPIPE_SZ`; set-before-arm remembered + applied on pipe creation, persists across `stop_interrupts` re-arm); `t/75` get/set/validation coverage; `make test` 214 PASS; hardware-verified (1 MiB before arm, persisted, round-trip). Downstream: `$pi->interrupt_buffer` (process-wide → Pi object) + FAQ "Bursts and dropped edges". Earlier same day: **V13 PASS** (`last_interrupt()`, promoted from B1): widened the self-pipe record to carry `pinBCM` + `statusOK` (now 24-byte `"i I i i q"`); `last_interrupt()` returns `{pin, pin_bcm, edge, status, ts_us}` for the most recent dispatched event (published before the callback, so a callback can query it), exported + reset by `stop_interrupts`; `t/75`/POD/examples updated; `make test` 209 PASS; hardware-verified (`pin_bcm`==17, copy isolation, undef states). Downstream: `$pi->last_interrupt` on RPi::WiringPi (process-wide → Pi object, not RPi::Pin). Earlier same day: **V12 PASS** (downstream OO + fork-safe cleanup): `RPi::WiringPi::Core::cleanup` now no-ops when `{proc} != $$` so a forked child can't run the parent's teardown; added `$pi->auto_dispatch_interrupts` (RPi::WiringPi) + `$pin->background_interrupt` (RPi::Pin), with POD/FAQ/Changes. Hardware: witness pin stayed OUTPUT/HIGH after the background child exited (guard proven); auto-dispatch 10/10; non-fork `t/200` still green. `auto_dispatch_interrupts` intentionally NOT on RPi::Pin (process-global switch). Earlier same day: **V10 + V11 PASS** (upstream, additive) — implemented `background_interrupt($pin,$edge,$cb,$debounce_us)` (forks, arms in child, runs `$cb` per edge; returns a `WiringPi::API::BackgroundInterrupt` handle with idempotent `stop`/`pid`/`running`; DESTROY + END reap the child) and `auto_dispatch_interrupts($bool)` (SIGIO async mode on the read fd + `$SIG{IO}` drain; lock-free safe-point dispatch; restores prior handler on disable). Hardware exerciser on Pi 5: auto-dispatch fired 10/10 edges with no loop and stopped after disable; background child handled the edges, `running`/`stop`/idempotency all correct; pre-fork validation croaks. `make test` = 207 PASS incl. `t/75-interrupts.t`; podchecker clean; POD adds the two functions + scenario-7/8 examples; Changes updated. **Gotcha fixed:** `fcntl(F_SETOWN, $$)` failed ESRCH because `$$` had been stringified elsewhere (Perl passed a pointer) → force `0 + $$`. **Discovery → new V12:** RPi::WiringPi cleanup isn't fork-aware, so OO exposure of `background_interrupt` needs that guard first. **V9 PASS** — fixed downstream and re-ran the gate on real Pi 5 hardware: all three interrupt suites' interrupt assertions pass (`t/200` rising ×3, `t/201` falling ×3, `t/202` both 2/4/6) under the new explicit-dispatch model. Downstream changes (working tree, uncommitted): **RPi::Pin** (`~/repos/rpi-pin`) `set_interrupt` now requires a CODE ref + validates `$edge`/`$callback`/`$debounce_us` and passes debounce through; `interrupt_set` delegates correctly (was passing pin as edge). **RPi::WiringPi** (`~/repos/rpi-wiringpi`) gained `wait_interrupts`/`dispatch_interrupts`/`stop_interrupts` proxy methods; `RPi::WiringPi::Core::cleanup` now calls `stop_interrupts()` (**B8** done); FAQ + POD + `t/200-202` + `defacto_interrupt.pl` updated to coderef + dispatch; Changes entries added in both repos. **Caveat (orthogonal, not V9):** the suites also run `rpi_check_pin_status`, which fails on this Pi because RPiTest's hardcoded `rpi_default_pin_config` doesn't match the board's actual default alt-modes (e.g. pin 2 alt=0 vs 4, pins 14/15/23/24/25 alt=31) — reproduced with a bare `setup_gpio`+`get_alt`, no interrupts involved; out of scope here. Ran via `PERL5LIB` pointing at wiringpi-api `blib` (bypasses the installed-`.so` executable-stack error, V33). Prior: V8 PASS (real-hardware full gate + `t/75-interrupts.t`, valgrind clean); V7/V6/V5/V4/V3/V2/V1 PASS. **Changes kept current per-task**; `isr-examples-final.md` awaits commit; nothing committed yet (all in working tree). Drain contract for V5/V8: EINTR→retry, other-errno→remove+stop, EOF→remove+stop.
> **ARCHIVE:** See isr-migration-archive.md for completed V tasks (V1-V17, V20 archived)

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
| V18 | **Refresh `isr-examples-final.md` + emit `lib/INTERRUPTS.pod` (wiringpi-api).** Update `isr-examples-final.md` for everything added (V10-V17: `background_interrupt`/`background_interrupts`/results, `auto_dispatch_interrupts`, `last_interrupt`, `interrupt_buffer`, `run_interrupt_loop`/`stop_interrupt_loop`, the 24-byte record) AND fold in the **code-flow section** from `isr-migration.md` (Perl→API.pm→API.xs→wiringPi). Then produce a POD copy at `lib/INTERRUPTS.pod`, omitting the top "Status" section and the bottom "What changed vs ..." section, but **keeping** the code-flow section. | `podchecker lib/INTERRUPTS.pod`; examples doc matches the shipped API | examples current incl. code-flow; INTERRUPTS.pod clean, right sections omitted | ⏳ (do last) |
| V19 | **`lib/INTERRUPTS.md` for rpi-wiringpi + rpi-pin.** Create an interrupt guide in each downstream repo, each reflective of its own surface — RPi::WiringPi: the `$pi` process-level methods (wait/dispatch/stop, auto_dispatch_interrupts, last_interrupt, interrupt_buffer, run_interrupt_loop/stop, background_interrupts) + cleanup/fork notes; RPi::Pin: the `$pin` methods (set_interrupt, background_interrupt incl. results). **No code-flow section** in either (that's wiringpi-api-only). | `ls rpi-wiringpi/lib/INTERRUPTS.md rpi-pin/lib/INTERRUPTS.md`; content matches each module's API | both guides exist, module-specific, no code-flow | ⏳ (do last) |

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
                    while (sysread interrupt_fd, $buf, 24) { ($pin,$pin_bcm,$edge,$status,$ts)=unpack"i I i i q",$buf;
                                                              $_last_interrupt={...}; $_interrupt_cb{$pin}->($edge,$ts); }   # $pin==0 -> matches
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

    auto_dispatch_interrupts(1);     # enable: wire the interrupt fd to a signal + install handler
    auto_dispatch_interrupts(0);     # disable: restore fd flags + the prior signal handler

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

- **Claims a process signal.** `SIGIO` is process-global; `auto_dispatch_interrupts` saves and
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
`background_interrupt`. So: `auto_dispatch_interrupts` = in-process + shared state + no loop;
`background_interrupt` = separate process, fires even during long C; cooperative
`dispatch_interrupts` = explicit control.

## Discovery Tracking

- ✅ RESOLVED in **V9** (2026-06-05): the downstream-breaking finding (RPi::Pin passed a **string** handler the new `set_interrupt` rejects; no auto-fire) is fixed downstream per the 2026-06-04 decision — RPi::Pin now requires a coderef, RPi::WiringPi exposes `wait_interrupts`/`dispatch_interrupts`/`stop_interrupts`, `cleanup` calls `stop_interrupts()` (**B8 done**), tests/FAQ/POD updated; all three interrupt suites green on hardware. Details in the archived V9 bullet. **UPGRADE-3.18 V33 is the same gate — update it there too.**

- ✅ RESOLVED in **V7**: the `EDGE_RISING` vs `INT_EDGE_*` naming mismatch (raised in V2). The design-section examples here now use `INT_EDGE_RISING`; `isr-examples-final.md` already used `INT_EDGE_*`; the POD documents the `INT_EDGE_*` constants. No `EDGE_*` aliases added — `INT_EDGE_*` (wiringPi's own names) is canonical.

## Backlog

B1: *(promoted to V13 — stats accessor `last_interrupt()`; slot retired)*

B2: *(promoted to V14 — overflow/coalescing policy documented + `interrupt_buffer()` sizing; slot retired)*

B3: *(promoted to V15 — `run_interrupt_loop()`/`stop_interrupt_loop()` dispatch-loop helper; slot retired)*

B4: *(promoted to V16 — `background_interrupts()` shared child for many pins + control channel; slot retired)*

B5: *(promoted to V17 — `background_interrupt` opt-in `results` data-back channel; slot retired)*

B6: *(promoted to V20 — `auto_dispatch_interrupts` configurable signal + per-`set_interrupt` opt-in; slot retired)*

B8: *(✅ RESOLVED — see Archived Fixes. Wired into RPi::WiringPi cleanup in V9, made fork-safe in V12, cleanup POD updated 2026-06-05; slot retired.)*

## Explicitly NOT doing

- **Calling Perl from the wiringPi ISR thread** (the old `mine` + dispatcher model) — the hazard this whole redesign removes; the foreign thread only `write()`s.
- **A C dispatcher thread of our own** — the kernel pipe + the consuming interpreter replace it; no thread to create, race, or join.
- **Requiring threaded Perl** — works everywhere; background handling uses `fork`. ithread-based concurrency is parked (`threads-patch.md` / `threads-examples.md`).
- **`initThread` / general threads / ithreads** — separate concern, **parked**; see `threads-patch.md` and `threads-examples.md`.
