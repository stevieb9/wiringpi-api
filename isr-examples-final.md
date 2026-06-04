# WiringPi::API — interrupt (ISR) usage examples

> **Status — design-stable, implementation-provisional.** The example *patterns*
> below are settled and consistent with the spec (`isr-migration.md`); the **API
> they call is not implemented yet** (validation tasks V1–V11 pending) and
> names/signatures are subject to verification. As of this writing `API.xs` still
> ships the older dispatcher-thread design these examples replace, so the snippets
> here **will not run until the self-pipe rewrite lands**. This doc is **ISR-only
> and uses no `use threads`** — general concurrency/worker examples live in
> `threads-examples.md` (currently parked).

## Table of contents

- [About these examples](#about-these-examples)
- [Decision guide](#decision-guide)
- [Reacting to interrupts](#reacting-to-interrupts)
  - [1. Cooperative dispatch in your main loop](#1-cooperative-dispatch-in-your-main-loop)
  - [2. Blocking wait loop](#2-blocking-wait-loop)
  - [3. Event-loop integration with the interrupt fd](#3-event-loop-integration-with-the-interrupt-fd)
  - [4. Multiple pins and callbacks](#4-multiple-pins-and-callbacks)
  - [5. Edge types and debounce](#5-edge-types-and-debounce)
  - [6. Teardown and re-arming](#6-teardown-and-re-arming)
- [Hands-off handling (no dispatch loop)](#hands-off-handling-no-dispatch-loop)
  - [7. Fire with no loop (auto_dispatch)](#7-fire-with-no-loop-auto_dispatch)
  - [8. A background process (background_interrupt)](#8-a-background-process-background_interrupt)
  - [9. Under the hood: manual fork](#9-under-the-hood-manual-fork)
- [Non-threaded Perl](#non-threaded-perl)
- [Anti-patterns to avoid](#anti-patterns-to-avoid)
- [API reference for these examples](#api-reference-for-these-examples)
- [What changed vs `isr-examples.md`](#what-changed-vs-isr-examplesmd)

## About these examples

- **Interrupts never require `use threads`.** wiringPi runs its own C threads
  internally and writes events to a pipe; your Perl reads that pipe. Hands-off
  handling uses an in-process signal (scenario 7) or a forked process (scenario 8)
  — never threads.
- **Callbacks receive `($edge, $timestamp_us)`** — the edge that fired
  (`INT_EDGE_FALLING`=1 / `INT_EDGE_RISING`=2) and a microsecond timestamp.
- **Pin numbering** follows whichever setup you call: `setup()` = wiringPi
  numbering, `setup_gpio()` = BCM. Examples use `setup()`.
- **Mode constants** for `pin_mode`: `INPUT`=0, `OUTPUT`=1 (shown as integers).
- **To hide the most work, prefer the hands-off options.** `auto_dispatch`
  (scenario 7) fires callbacks in your own process with no loop; `background_interrupt`
  (scenario 8) runs an independent handler in its own process. Scenario 9 is the
  manual version of 8. Sections 1–6 (cooperative) explain the explicit dispatch
  model that 7 and 8 hide — read them to understand what happens under the
  hands-off calls, but **most programs only need 7 or 8.**
- **If you fork yourself** (scenario 9): call `setup()` and `pin_mode` in the
  parent **before** forking, and arm the interrupt in the child that dispatches it.
- An **ithread**-based background alternative exists but lives in
  `threads-examples.md`, which is parked behind the ISR work.

## Decision guide

None of these need `use threads`. To hide the most plumbing, prefer the first two
(hands-off) rows.

> **7 vs 8 in one line:** `auto_dispatch` (7) gives you lock-free shared state but
> *defers* during a long non-yielding C call; `background_interrupt` (8) fires
> regardless of what main is doing but **can't touch main's variables**. No long C
> calls? Pick 7. Long C calls? Pick 8.

| What you want | Scenario |
|---|---|
| Attach a handler and forget it; it updates my program's state | [7](#7-fire-with-no-loop-auto_dispatch) (`auto_dispatch`) |
| Independent handler that fires even during long/blocking work | [8](#8-a-background-process-background_interrupt) (`background_interrupt`) |
| React to a pin while running my own loop, on my terms | [1](#1-cooperative-dispatch-in-your-main-loop), [3](#3-event-loop-integration-with-the-interrupt-fd) |
| A program whose only job is reacting to pins | [2](#2-blocking-wait-loop) |
| Several pins, each with its own handler | [4](#4-multiple-pins-and-callbacks) |
| Specific edges / debounce a noisy input | [5](#5-edge-types-and-debounce) |
| Tear down or re-arm a pin | [6](#6-teardown-and-re-arming) |
| Deliver edges back to the parent to handle there | [9](#9-under-the-hood-manual-fork) |

---

## Reacting to interrupts

### 1. Cooperative dispatch in your main loop

**Why/when:** You already have a main loop and want to control exactly when
callbacks run. Simplest model, works on any Perl — but a callback only fires when
you call `dispatch_interrupts()`, so keep the loop snappy. (Want it fully
hands-off? See scenario 7.)

**Real-world:** A rover whose main loop steers and reads sensors every tick, while
a front bumper microswitch triggers an obstacle-avoidance routine — serviced once
per loop pass.

**Main & interrupt:** One thread. The callback runs *inside* `dispatch_interrupts()`,
so it can read/write any of main's variables with no locking — but it only fires
when main calls dispatch, and it blocks main while it runs.

Do your own work, and fire any pending interrupt callbacks each pass.

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode set_interrupt dispatch_interrupts INT_EDGE_RISING);

setup();
pin_mode(0, 0);            # INPUT

set_interrupt(0, INT_EDGE_RISING, sub {
    my ($edge, $ts_us) = @_;
    print "pin 0 rising at ${ts_us}us\n";
});

while (1) {
    do_other_work();
    dispatch_interrupts();  # non-blocking: runs callbacks for any events that arrived
}

sub do_other_work {
    # ... your periodic work ...
}
```

Tradeoff: if `do_other_work()` blocks for a long time, callbacks wait until the
next `dispatch_interrupts()`. Conversely, if `do_other_work()` returns instantly
with nothing to do, this loop **busy-spins at 100% CPU** — pace it with real
periodic work, a short `sleep`, or by `select`ing on `interrupt_fd` with a timeout
(scenario 3).

### 2. Blocking wait loop

**Why/when:** Reacting to pins *is* the whole job — there's no other work to do.
The process sleeps efficiently until an edge arrives.

**Real-world:** A doorbell or panic button — the Pi idles at near-zero CPU until
the button fires, then sends a notification.

**Main & interrupt:** One thread. Main is blocked in `wait_interrupts()` until an
edge, then runs the callback inline (full access to program state). Main does no
other work while it waits.

When reacting to pins *is* the program. `wait_interrupts` blocks until an event
arrives (or the timeout), then dispatches.

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_BOTH);

setup();
pin_mode(0, 0);            # INPUT

set_interrupt(0, INT_EDGE_BOTH, \&on_change);

while (1) {
    wait_interrupts(1000);  # block up to 1000ms, dispatch whatever fired
}

sub on_change {
    my ($edge, $ts_us) = @_;
    print "edge $edge at ${ts_us}us\n";
}
```

### 3. Event-loop integration with the interrupt fd

**Why/when:** You already run an event loop (AnyEvent/IO::Async) or juggle
sockets/timers, and want GPIO to be just another fd in it.

**Real-world:** A home-automation daemon already running an `IO::Async` loop for
MQTT/HTTP that also publishes a message when a PIR motion sensor trips.

**Main & interrupt:** One thread (the loop). The callback runs inline when the loop
reaches the fd — full shared access; latency depends on the loop, and main must not
block it elsewhere.

`interrupt_fd()` returns a read fd you can `select`/poll alongside your other
descriptors — so one loop handles sockets, timers, and GPIO together.

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode set_interrupt dispatch_interrupts interrupt_fd INT_EDGE_RISING);

setup();
pin_mode(0, 0);            # INPUT
set_interrupt(0, INT_EDGE_RISING, \&on_edge);

my $fd = interrupt_fd();
vec(my $mask = '', $fd, 1) = 1;

while (1) {
    select(my $ready = $mask, undef, undef, undef);  # block until readable
    if (vec($ready, $fd, 1)) {
        dispatch_interrupts();
    }
}

sub on_edge {
    my ($edge, $ts_us) = @_;
    print "edge!\n";
}
```

The same `$fd` plugs into `AnyEvent->io` or `IO::Async::Handle`.

### 4. Multiple pins and callbacks

**Why/when:** Several inputs, each with its own handler, serviced by one loop.
(Same mechanics as 1–3; this just shows the fan-out.)

**Real-world:** A control panel with Start/Stop/Up/Down buttons, each wired to its
own handler.

**Main & interrupt:** Still one servicing thread — callbacks run one at a time with
full access to main's state; no callback runs concurrently with another or with
main.

One pipe, one loop, many pins — each with its own callback.

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts
                     INT_EDGE_RISING INT_EDGE_FALLING INT_EDGE_BOTH);

setup();
pin_mode($_, 0) for (0, 2, 3);   # INPUT

set_interrupt(0, INT_EDGE_RISING,  sub { print "button A\n" });
set_interrupt(2, INT_EDGE_FALLING, sub { print "button B\n" });
set_interrupt(3, INT_EDGE_BOTH,    \&sensor);

while (1) {
    wait_interrupts(1000);
}

sub sensor {
    my ($edge, $ts_us) = @_;
    print "sensor edge=$edge\n";
}
```

### 5. Edge types and debounce

**Why/when:** You care about a specific edge, or the input is electrically noisy
(a button) and you want the kernel to suppress bounce so the callback fires once
per press.

**Real-world:** Counting items on a conveyor with a microswitch (or reading a
rotary encoder) — debounce gives one event per actuation instead of a burst from
contact bounce.

**Main & interrupt:** Orthogonal to where the callback runs — debounce drops bounce
edges in the kernel before they're ever queued, so fewer events reach your dispatch
point.

Edge constants: `INT_EDGE_FALLING`=1, `INT_EDGE_RISING`=2, `INT_EDGE_BOTH`=3.
An optional 4th argument sets a **kernel debounce period** in **microseconds**
(default 0 = off). wiringPi applies it as a Linux **GPIO-v2 line attribute**
(`GPIO_V2_LINE_ATTR_ID_DEBOUNCE`) at arm time (`wiringPi.c`, in
`interruptHandlerInit`), so the kernel drops bounce edges before they reach the
pipe — it is *not* a hardware debounce. The attribute's field is a `u32`, so the
effective maximum is ~2³² µs (≈ 71 minutes) — unlimited for any real use.

```perl
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_FALLING);

setup();
pin_mode(0, 0);

# debounce a noisy button: ignore repeat edges within 5ms
set_interrupt(0, INT_EDGE_FALLING, \&pressed, 5000);

wait_interrupts(1000) while 1;

sub pressed {
    print "clean press\n";
}
```

### 6. Teardown and re-arming

**Why/when:** You need to stop watching a pin, swap a handler at runtime, or clean
up on exit.

**Real-world:** A handheld with a mode button — swap its handler when switching
screens, and `stop_interrupts()` on shutdown to release the lines.

**Main & interrupt:** `stop_interrupt`/re-arm run in main and edit the registration;
after a stop the callback can't fire, and re-arming swaps it cleanly (the old
listener is stopped first).

```perl
set_interrupt(0, INT_EDGE_RISING, \&handler_a);

# Re-arm the same pin with a different handler — the old listener is stopped
# automatically first, so no stacked/duplicate registration:
set_interrupt(0, INT_EDGE_RISING, \&handler_b);

stop_interrupt(0);    # stop one pin, forget its callback
stop_interrupts();    # stop every pin, drain + close the pipe
```

Optional: `interrupt_dropped()` returns a count of events dropped because the
pipe was full (bursts faster than you dispatch).

---

## Hands-off handling (no dispatch loop)

### 7. Fire with no loop (auto_dispatch)

**Why/when:** The most hands-off in-process option — "attach a handler and forget
it," closest to Arduino's `attachInterrupt`. The callback runs in *your* program
(it can read/update your variables, no locking) and fires on its own while your
code runs, with no dispatch loop. Best when a handler must touch your program's
state. Caveat: a long non-yielding C/XS call can delay it (see `isr-migration.md`).

**Real-world:** A weather station counting anemometer/rain-gauge pulses into a
counter your main loop reads and uploads every few seconds — the handler updates
your in-program state directly.

**Main & interrupt:** The callback runs in **main's interpreter** at op boundaries
(and on interrupted sleeps), so it can read/write main's variables with **no
locking** — but a long non-yielding C call defers it until that call returns.

`auto_dispatch(1)` wires the interrupt fd to a signal and installs the handler for
you, so `set_interrupt` callbacks fire **automatically, in your own process**, with
no `dispatch_interrupts`/`wait_interrupts` loop. Perl runs them at safe points
(between ops, and on interrupted sleeps), so the callback can touch your variables
with **no locking**.

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode set_interrupt auto_dispatch INT_EDGE_RISING);

setup();
pin_mode(0, 0);            # INPUT

auto_dispatch(1);          # callbacks now fire on their own — no loop to write

my $count = 0;
set_interrupt(0, INT_EDGE_RISING, sub { $count++ });   # updates your own variable

while (1) {
    do_main_work();        # the callback fires between ops, and during the sleep
    print "edges so far: $count\n";
    sleep 1;
}

sub do_main_work {
    # ...
}
```

No dispatch loop, no fork, no threads — and the callback shares your program's
state directly. The one caveat: a long, non-yielding C/XS call delays the callback
until it returns (it fires at Perl's safe points). To fire even during such work,
use scenario 8.

### 8. A background process (background_interrupt)

**Why/when:** True fire-while-busy with zero servicing, even during long blocking
work — because the handler runs in a *separate process*. Best for **independent**
handlers (drive a pin, log, notify) that don't need your main program's variables.

**Real-world:** An emergency-stop button that drops a motor relay immediately — it
must fire even while main is mid-way through a long upload or computation, and the
handler just drives a GPIO.

**Main & interrupt:** The callback runs in a **separate process**, truly
concurrently — it fires even while main blocks, but **cannot** see or change main's
variables (separate memory; share via IPC). Neither can corrupt the other.

`background_interrupt` hides the fork, the wait loop, and the cleanup: give it a
pin, an edge, and a callback, and it runs that callback in a background process on
each edge while your main program does whatever it likes. **The callback runs in
the background process** — ideal for independent handlers (drive a pin, log, send
a message); it can't touch your main program's variables.

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode background_interrupt INT_EDGE_RISING);

setup();
pin_mode(0, 0);            # INPUT

my $h = background_interrupt(0, INT_EDGE_RISING, sub {
    my ($edge, $ts_us) = @_;
    # runs in the background on each rising edge — independent work only
});

# main carries on; the handler fires on its own
for (1 .. 10) {
    do_other_work();
    sleep 1;
}

$h->stop;                  # stops + reaps the background handler

sub do_other_work {
    # ...
}
```

No `pipe`, no `fork`, no `select`, no `waitpid` — the library owns all of it (and
an `END` hook reaps the child even if you forget `stop`). `$h->stop` is
**idempotent**: safe to call more than once, and safe after the child has already
exited (it won't croak on an already-reaped handler). Needs no threaded Perl.
If a handler must report a value back to main, use scenario 9.

### 9. Under the hood: manual fork

**Why/when:** You rarely write this by hand — it's what scenario 8 does for you.
Use it directly only when you need each edge **delivered back to the parent** to
handle there, rather than handled in the child.

**Real-world:** A logger that timestamps every edge into the parent's open CSV/DB
handle — the child forwards edges over the pipe and the parent, which owns the
handle, writes them.

**Main & interrupt:** The child runs the wiringPi handler and only forwards events;
**main** runs your real logic when it drains the pipe (in main's interpreter, full
access to its state and handles). The child can't touch main's variables.

This is essentially what scenario 8 does for you, by hand — and the pattern to use
directly when you need each edge **delivered back to the parent** (main reacts),
rather than handled in the child. The child forwards edges over a pipe; the parent
drains and dispatches.

```perl
use strict;
use warnings;
use IO::Select;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_RISING);

setup();
pin_mode(0, 0);                          # INPUT — plain config, before fork

# This $rx/$tx pipe is YOUR OWN results channel (child -> parent), separate from
# the library's internal self-pipe (a fixed 16-byte {pin,edge,ts} record). You
# choose this channel's format; here, one newline-terminated text line per edge —
# self-delimiting, and portable (no 64-bit pack template, no fixed-width framing
# to get wrong).
pipe(my $rx, my $tx) or die "pipe: $!";

my $pid = fork // die "fork: $!";

if ($pid == 0) {
    # Child owns interrupt handling; arm HERE (post-fork). Only the child reads
    # the library's interrupt fd — the parent never calls dispatch on it.
    close $rx;
    set_interrupt(0, INT_EDGE_RISING, sub {
        my ($edge, $ts_us) = @_;
        syswrite $tx, "$edge $ts_us\n";          # one text line up to the parent
    });
    wait_interrupts(1000) while 1;
    exit 0;
}

# Parent: free to work; drain results without blocking.
close $tx;
my $sel = IO::Select->new($rx);
my $buf = '';

# Reap the child on normal exit/die even if you forget to stop it explicitly.
# (Not run on signal-kill — trap signals too if you need that.)
END { if ($pid) { kill 'TERM', $pid; waitpid $pid, 0; $pid = undef; } }

while (1) {
    do_other_work();

    while ($sel->can_read(0)) {
        my $n = sysread($rx, my $chunk, 4096);
        if (!defined $n) {
            last if $!{EINTR};                        # signal: retry next pass ($buf intact)
            $sel->remove($rx); last;                  # any other error: stop, don't spin
        }
        if ($n == 0)     { $sel->remove($rx); last }  # EOF: child exited — stop watching
        $buf .= $chunk;
        while ($buf =~ s/^([^\n]*)\n//) {             # consume only complete lines
            my ($edge, $ts_us) = split ' ', $1;
            print "edge $edge at ${ts_us}us\n";
        }
    }
}

sub do_other_work {
    # ... your work ...
}
```

**One reader of the interrupt fd.** After the fork, only the *child* reads the
library's interrupt fd (it owns dispatch). The parent reacts through the results
pipe `$rx`, **never** by calling `dispatch_interrupts()` on the shared fd — two
readers would race for the same records.

**Backpressure.** `$tx` is a blocking pipe. If the parent stalls in
`do_other_work()` and stops draining `$rx`, the child's callback blocks in
`syswrite`, stops servicing its own internal self-pipe, and edges start dropping
(visible to the child via `interrupt_dropped()`). Keep the parent draining — or
set `$tx` non-blocking and handle `EAGAIN` if you'd rather drop than block.

**Don't busy-spin.** As in scenario 1, this loop's pace is set by
`do_other_work()`. If that can return instantly, do real periodic work, add a
short `sleep`, or `select` on `$rx` with a timeout (`$sel->can_read($secs)`) so the
parent sleeps when idle instead of spinning on `can_read(0)`.

> **High-rate alternative.** For very high edge rates you can use fixed binary
> records (`pack`/`unpack`) instead of text — but only if your Perl has 64-bit-IV
> support (the `q`/`Q` template, *not* present on every 32-bit Pi build) and each
> record stays ≤ `PIPE_BUF` (so writes remain atomic and reads stay
> record-aligned). Text framing avoids both constraints and is the better default.

> An `ithread`-based equivalent (shared variables instead of a results pipe) is in
> `threads-examples.md`, which is parked until the ISR work lands.

---

## Non-threaded Perl

The interrupt API needs nothing special. Everything in this doc — including
background handling via `auto_dispatch` (7) or `fork` (8) — works on a Perl built **without**
ithreads. "Background" does not imply `use threads`; only the ithread variants in
`threads-examples.md` do.

## Anti-patterns to avoid

- **Forgetting to service the fd in cooperative mode.** If you never call
  `dispatch_interrupts()`/`wait_interrupts()`, callbacks never fire — there is no
  background process doing it for you unless you set one up (scenarios 7-8).
- **Forking *after* arming interrupts.** wiringPi's ISR pthreads don't survive
  `fork`, and a mutex held at fork time is left locked in the child. Fork first,
  then arm in the child that dispatches.
- **Sharing one device fd across forked processes.** An i2c/spi/serial handle
  should be used by a single process; two processes transacting on it interleave.
- **Two processes reading the same interrupt fd.** After a `fork`, exactly one
  context should drain the library's interrupt fd (scenario 9: the child). A
  second reader steals records from the first.
- **Relying on `auto_dispatch` during a long non-yielding C/XS call.** Its
  callbacks fire at Perl's safe points (op boundaries, interrupted sleeps); a long
  C call that never yields delays them. Use `background_interrupt` (separate
  process) if a handler must fire during such work.
- **Enabling `auto_dispatch` when your program already uses `SIGIO`/`O_ASYNC`.**
  It claims that signal; pick one owner (or use the real-time-signal option).
- **Busy-spinning a `do_work + poll` loop.** A `while (1) { do_other_work();
  dispatch_interrupts() }` (scenario 1) or `can_read(0)` drain (scenario 9) burns
  100% CPU if the work returns instantly. Pace it, sleep, or select with a timeout.

## API reference for these examples

| Call | Purpose | Returns † |
|---|---|---|
| `setup()` / `setup_gpio()` | init (wiringPi / BCM numbering); once, in main | int status (`0` = ok) |
| `pin_mode($pin, $mode)` | `0`=INPUT, `1`=OUTPUT | — |
| `digital_write($pin, $val)` / `digital_read($pin)` | pin I/O | — / pin level (`0`/`1`) |
| `set_interrupt($pin, $edge, $cb [, $debounce_us])` | arm; `$cb->($edge, $ts_us)` | true on success |
| `background_interrupt($pin, $edge, $cb [, $debounce_us])` | run the handler in a forked child | handle `$h` (`$h->stop` / `$h->pid` / `$h->running`) |
| `auto_dispatch($bool)` | fire `set_interrupt` callbacks automatically in-process (via `SIGIO`); no loop | — |
| `wait_interrupts($timeout_ms)` | block until event/timeout, then dispatch | count dispatched (`0` on timeout) |
| `dispatch_interrupts()` | non-blocking: dispatch pending events | count dispatched |
| `interrupt_fd()` | read fd for `select`/event loops | int fd |
| `interrupt_dropped()` | count of events dropped on a full pipe | int count |
| `stop_interrupt($pin)` / `stop_interrupts()` | teardown | — |
| `INT_EDGE_FALLING` (1) / `INT_EDGE_RISING` (2) / `INT_EDGE_BOTH` (3) | edge constants | int |

> † **Return values are provisional.** `isr-migration.md` does not yet pin down the
> return contract for `wait_interrupts` / `dispatch_interrupts`; the counts above
> are the *intended* behavior, to be confirmed when V5/V7 implement and document
> them. Keep this table, the spec, and the eventual XS/PM in sync — a doc that
> promises a return the code doesn't make is worse than one that stays silent.

> Names/signatures are provisional — see `isr-migration.md` for the authoritative,
> evolving definitions. For worker threads, shared state, and periodic events, see
> `threads-examples.md` (parked).

## What changed vs `isr-examples.md`

This file is the reviewed finalization of `isr-examples.md`. Each change below is a
correctness or clarity fix agreed during review; line references are to the
original.

1. **Status banner → two distinct claims.** "design-stable (patterns settled) /
   implementation-provisional (API unimplemented; `API.xs` still ships the old
   dispatcher-thread design)." The original's single "provisional" buried the lede
   that the snippets won't run yet.
2. **Debounce is kernel, not hardware** (orig. lines 227, 239). Verified against
   `wiringPi.c`: `interruptHandlerInit` sets `GPIO_V2_LINE_ATTR_ID_DEBOUNCE` on the
   GPIO-v2 line request, so the *kernel* debounces. "In the kernel" (orig. 235)
   was already correct and is kept; "hardware" is corrected. Added the `u32`
   (~2³² µs ≈ 71 min) range.
3. **Scenario 9 → newline-delimited text framing** (was `pack('l q')` / `unpack`).
   Fixes two things at once: (a) the `q`/`Q` pack template needs a 64-bit-IV Perl
   and can **croak at compile time** on a 32-bit Pi build; (b) self-delimiting text
   removes all fixed-width framing reasoning. Matches the spec's own example
   (`isr-migration.md:153`). Binary records kept as a documented high-rate footnote.
4. **Scenario 9 EOF & error handling.** The original drain (`last if !sysread`)
   busy-spins once the child closes the pipe (EOF stays "readable"). The new drain
   distinguishes three cases: `undef` + `EINTR` → retry next pass (`$buf` intact);
   `undef` + any other errno → `$sel->remove` (terminal, like EOF — otherwise a
   persistent error such as `EBADF` spins through `do_other_work` with nowhere to
   sleep); `0` (EOF) → `$sel->remove`. A dead child *or* a hard read error stops the
   spin.
5. **Backpressure note** added to scenario 9: a stalled parent blocks the child's
   `syswrite`, which backpressures the internal self-pipe and silently drops edges
   — observable via `interrupt_dropped()`.
6. **`END`-block reaper** in scenario 9 (was a comment) so a forgotten child is
   reaped on normal exit/die; clears `$pid` after `waitpid` so a second END pass
   (e.g. a failed `exec`) can't double-reap; noted that scenario 8 does this for you.
7. **Single-reader note** (scenario 9 + anti-patterns): after fork only the child
   reads the interrupt fd; the parent uses the results pipe.
8. **7-vs-8 tradeoff line** at the top of the decision guide, plus a "most programs
   only need 7 or 8" signpost in *About* — **without** reordering 1–6 (they define
   the model 7/8 hide).
9. **Two-channels clarification** in scenario 9: the `$rx`/`$tx` results pipe is the
   user's own channel, distinct from the internal 16-byte self-pipe; its format is
   independent.
10. **Return-value column** in the API reference (flagged provisional, with the
    "keep doc/spec/XS in sync" warning) — the original documented no return values.
11. **`$h->stop` idempotency** noted in scenario 8; **busy-spin** caveat added to
    scenarios 1 and 9 and the anti-patterns list.
