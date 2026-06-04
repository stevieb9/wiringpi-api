# Plan: Migrate interrupts to `wiringPiISR2` via a self-pipe

> **NEXT ACTION:** V1 — on the Pi, confirm the installed `<wiringPi.h>` declares `wiringPiISR2` / `wiringPiISRStop` / `struct WPIWfiStatus` (≥ 3.16).
> **LAST SESSION:** **Rewritten 2026-06-03.** Replaced the earlier dispatcher-thread draft with a **self-pipe** design after a thread-safety audit (embedded below). The foreign (wiringPi) ISR thread now only `write()`s an event to a pipe; all Perl dispatch happens in the consuming interpreter's own thread. This dissolves F17/F18/F19 and makes the module work on **both threaded and non-threaded Perl**. Background handling is shown with `fork` (no threaded Perl); ithread-based concurrency is parked (see `threads-patch.md` / `threads-examples.md`).
> **ARCHIVE:** See isr-migration-archive.md for completed V tasks

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
| V1 | **Prereq gate (Pi, first).** Confirm installed `<wiringPi.h>` declares `wiringPiISR2`, `wiringPiISRStop`, `struct WPIWfiStatus` (≥ 3.16). No threaded-Perl requirement (self-pipe); background handling uses `fork`. | `grep -n "wiringPiISR2\|wiringPiISRStop\|WPIWfiStatus" /usr/include/wiringPi.h` | both ISR2 symbols + struct present | ⏳ |
| V2 | **Edge validation + constants (F23).** Validate `$edge` ∈ {`INT_EDGE_FALLING`=1, `RISING`=2, `BOTH`=3} (reject `SETUP`=0/junk); expose the four `INT_EDGE_*` constants to Perl. Order: `$pin`, then `$edge`, then `$callback`. | `perl -c -Ilib lib/WiringPi/API.pm` + XS parse | syntax/XS OK; bad edge croaks; constants importable | ⏳ |
| V3 | **Wrap `wiringPiISRStop(int pin)`.** Thin XS wrap + `@wpi_c_functions` export. Needed for re-arm + teardown. (`waitForInterruptClose` is a legacy alias — wrap only `wiringPiISRStop`.) | XS parse + `perl -c` | XS parses; symbol present | ⏳ |
| V4 | **Self-pipe core (F12 / F10 / F22).** Create a `pipe2()` (or `pipe`+`O_NONBLOCK`) at first arm; write end non-blocking. Add one generic `isr2_writer(struct WPIWfiStatus, void *userdata)` that builds a fixed record `{int pin; int edge; long long ts_us;}` (pin from `userdata`, **not** `wfiStatus.pinBCM`) and `write()`s it (count drops on `EAGAIN`). `_arm_interrupt(pin, edge, debounce)` calls `wiringPiISRStop(pin)` if re-arming, then `wiringPiISR2(pin, edge, isr2_writer, debounce, (void*)(intptr_t)pin)`. Expose `interrupt_fd()` (read end). **Delete** the 40 trampolines + `interrupt_handlers[]` + `MAKE_HANDLER`/`APPLY_TO_PINS`, the dead `interruptHandler()` (+ API.h decl + export), and `mine`/`perl_callbacks[]`/`event_queue`/mutex/cond/dispatcher. | XS parse + `perl -c` + grep that `interruptHandler_`/`mine`/`perl_callbacks`/`event_queue` are gone | XS parses; only `wiringPiISR2` + pipe remain; no dispatcher/trampoline residue | ⏳ |
| V5 | **Perl-side dispatch.** Keep the callback registry in Perl: `set_interrupt($pin,$edge,$cb)` stores `$cb` in a lexical `%_interrupt_cb` (per-interpreter) then calls `_arm_interrupt`. Add `dispatch_interrupts()` (non-blocking: `sysread` all available 16-byte records from `interrupt_fd`, `unpack "i i q"`, call `$_interrupt_cb{$pin}->($edge, $ts_us)`) and `wait_interrupts($timeout_ms)` (`select` on the fd, then dispatch). Expose `interrupt_dropped()` (F24 overflow count). | `perl -c -Ilib lib/WiringPi/API.pm` | OK; dispatch reads records and fans out to callbacks | ⏳ |
| V6 | **Teardown.** `stop_interrupt($pin)` = `wiringPiISRStop(pin)` + `delete $_interrupt_cb{$pin}`. `stop_interrupts()` = stop all armed pins, drain + close the pipe, reset state. No thread to join (the win of this design). Exports. | XS parse + `perl -c` | parses; teardown subs present | ⏳ |
| V7 | **POD + concurrency contract.** Document `set_interrupt` (unchanged signature), `interrupt_fd`/`wait_interrupts`/`dispatch_interrupts`/`stop_interrupt(s)`, and the optional 4th `$debounce_us`. State plainly: single-threaded event-loop usage works on any Perl; for background handling, `fork` a child that arms + dispatches (no threaded Perl; see `isr-examples.md`). | `podchecker lib/WiringPi/API.pm` + `perl -c` | POD clean; both usage modes documented | ⏳ |
| V8 | **Full gate (Pi).** `perl Makefile.PL && make && make test`. Exercisers: (a) **single-threaded** — arm, drive edges, `wait_interrupts` loop dispatches correct callbacks under **both** `setup()` (wpi 0 = BCM 17) and `setup_gpio()`; (b) **fork** — a child arms + loops `wait_interrupts` while main does other work (proves true background handling); re-arm twice (no stacked listener); `stop_interrupt(s)` clean. `valgrind --leak-check=full`: no leaks, no leaked fds. Update Changes (`3.1801 UNREL`). | `perl Makefile.PL && make && make test` + exercisers (Pi) | green; correct dispatch in both modes + background via fork; no leaks; Changes updated | ⏳ |
| V9 | **Downstream gate (RPi::WiringPi).** Install converted module; run `t/200-interrupt_rising_and_pud.t`, `t/201-…falling…`, `t/202-…both…`, `build_testing/build/defacto_interrupt.pl`. Externally-observable behavior unchanged (rising/falling/both fire). Note new dispatch model if a consumer must call `wait_interrupts`. | `cd ~/repos/rpi-wiringpi && prove -Ilib t/200-interrupt_rising_and_pud.t t/201*.t t/202*.t` (Pi) | interrupt suite green on wired hardware | ⏳ |

## Example + code flow — Perl → `API.pm` → `API.xs` → wiringPi `wiringPi.c`

Illustrative C is target/post-rewrite. Worked numbers use `setup()` (wiringPi
numbering) where **wpi pin 0 = BCM 17**, showing why `userdata` (the caller's pin)
is the key, not `wfiStatus.pinBCM`.

### Two ways to consume (your choice of concurrency)

**Single-threaded / event-driven (any Perl):**
```perl
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts EDGE_RISING);
setup();
pin_mode(0, 0);
set_interrupt(0, EDGE_RISING, sub { my ($edge, $ts) = @_; print "edge=$edge at $ts us\n" });
wait_interrupts(1000) while 1;     # blocks on the fd, dispatches in THIS thread
```

**Background via `fork` (main stays free; no threaded Perl):**
```perl
use IO::Select;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts EDGE_RISING);

setup();                           # ONCE in main, before forking (audit contract)
pin_mode(0, 0);
pipe(my $rx, my $tx) or die "pipe: $!";

my $pid = fork // die "fork: $!";
if ($pid == 0) {                   # child owns the interrupt; arm HERE
    close $rx;
    set_interrupt(0, EDGE_RISING, sub { my ($e, $ts) = @_; syswrite $tx, "$ts\n" });
    wait_interrupts(1000) while 1; # dispatch here, concurrent with main
    exit 0;
}

close $tx;                         # parent: free to work; drain $rx when it likes
my $sel = IO::Select->new($rx);
while (1) {
    # ... main's own work ...
    while ($sel->can_read(0)) {
        last if ! sysread($rx, my $rec, 64);
        print "edge reported\n";
    }
}
```
(An ithread-based equivalent — shared vars instead of a pipe — is in
`threads-examples.md`, parked.)

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

## Discovery Tracking

_None yet._

## Backlog

B1: Pass the full `wfiStatus` to callbacks optionally — the record already carries edge + timestamp; consider a richer callback signature or a stats accessor.

B2: Coalescing policy — document/expose whether bursts beyond the pipe buffer coalesce; `interrupt_dropped()` already surfaces the count (F24).

B3: Provide a tiny built-in dispatch loop helper (e.g., `run_interrupt_loop()`) for users who don't want to write the `wait_interrupts while 1` themselves.

## Explicitly NOT doing

- **Calling Perl from the wiringPi ISR thread** (the old `mine` + dispatcher model) — the hazard this whole redesign removes; the foreign thread only `write()`s.
- **A C dispatcher thread of our own** — the kernel pipe + the consuming interpreter replace it; no thread to create, race, or join.
- **Requiring threaded Perl** — works everywhere; background handling uses `fork`. ithread-based concurrency is parked (`threads-patch.md` / `threads-examples.md`).
- **`initThread` / general threads / ithreads** — separate concern, **parked**; see `threads-patch.md` and `threads-examples.md`.
