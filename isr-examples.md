# WiringPi::API — interrupt (ISR) usage examples

> **Status:** illustrates the **planned** self-pipe interrupt API from
> `isr-migration.md`. Not implemented yet; names/signatures provisional. This doc
> is **ISR-only and uses no `use threads`** — general concurrency/worker examples
> live in `threads-examples.md` (currently parked).

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
- [Background interrupt handling](#background-interrupt-handling)
  - [7. Background interrupts via fork](#7-background-interrupts-via-fork)
- [Non-threaded Perl](#non-threaded-perl)
- [Anti-patterns to avoid](#anti-patterns-to-avoid)
- [API reference for these examples](#api-reference-for-these-examples)

## About these examples

- **Interrupts never require `use threads`.** wiringPi runs its own C threads
  internally and writes events to a pipe; your Perl reads that pipe. Background
  handling (scenario 7) uses `fork`, not threads.
- **Callbacks receive `($edge, $timestamp_us)`** — the edge that fired
  (`INT_EDGE_FALLING`=1 / `INT_EDGE_RISING`=2) and a microsecond timestamp.
- **Pin numbering** follows whichever setup you call: `setup()` = wiringPi
  numbering, `setup_gpio()` = BCM. Examples use `setup()`.
- **Mode constants** for `pin_mode`: `INPUT`=0, `OUTPUT`=1 (shown as integers).
- **If you fork** (scenario 7): call `setup()` and `pin_mode` in the parent
  **before** forking, and arm the interrupt in the child that dispatches it.
- An **ithread**-based background alternative exists but lives in
  `threads-examples.md`, which is parked behind the ISR work.

## Decision guide

None of these need `use threads`.

| What you want | Scenario |
|---|---|
| React to a pin while running your own loop | [1](#1-cooperative-dispatch-in-your-main-loop), [3](#3-event-loop-integration-with-the-interrupt-fd) |
| A program whose only job is reacting to pins | [2](#2-blocking-wait-loop) |
| Several pins, each with its own handler | [4](#4-multiple-pins-and-callbacks) |
| Specific edges / debounce a noisy input | [5](#5-edge-types-and-debounce) |
| Tear down or re-arm a pin | [6](#6-teardown-and-re-arming) |
| Interrupts handled while main is blocked/busy | [7](#7-background-interrupts-via-fork) (fork) |

---

## Reacting to interrupts

### 1. Cooperative dispatch in your main loop

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
next `dispatch_interrupts()`.

### 2. Blocking wait loop

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

Edge constants: `INT_EDGE_FALLING`=1, `INT_EDGE_RISING`=2, `INT_EDGE_BOTH`=3.
An optional 4th argument sets a hardware debounce period in **microseconds**
(default 0 = off).

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

## Background interrupt handling

### 7. Background interrupts via fork

To keep the main program free to block/compute while interrupts are handled,
`fork` a dedicated handler process. It is lossless (the kernel buffers the pipe)
and needs **no threaded Perl**. The child owns the interrupt; the parent drains a
results channel when it likes.

```perl
use strict;
use warnings;
use IO::Select;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_RISING);

setup();
pin_mode(0, 0);                          # INPUT — plain config, before fork

pipe(my $rx, my $tx) or die "pipe: $!";  # child -> parent results channel

my $pid = fork // die "fork: $!";

if ($pid == 0) {
    # child owns interrupt handling; arm HERE (post-fork)
    close $rx;
    set_interrupt(0, INT_EDGE_RISING, sub {
        my ($edge, $ts_us) = @_;
        syswrite $tx, pack('l q', $edge, $ts_us);   # 12-byte record up to parent
    });
    wait_interrupts(1000) while 1;
    exit 0;
}

# parent: free to work; drain results without blocking
close $tx;
my $sel = IO::Select->new($rx);

while (1) {
    do_other_work();

    while ($sel->can_read(0)) {
        last if ! sysread($rx, my $rec, 12);        # child gone
        my ($edge, $ts_us) = unpack 'l q', $rec;
        print "edge $edge at ${ts_us}us\n";
    }
}

# on shutdown: kill 'TERM', $pid; waitpid $pid, 0;

sub do_other_work {
    # ... your work ...
}
```

> An `ithread`-based equivalent (shared variables instead of a results pipe) is in
> `threads-examples.md`, which is parked until the ISR work lands.

---

## Non-threaded Perl

The interrupt API needs nothing special. Everything in this doc — including
background handling via `fork` (scenario 7) — works on a Perl built **without**
ithreads. "Background" does not imply `use threads`; only the ithread variants in
`threads-examples.md` do.

## Anti-patterns to avoid

- **Forgetting to service the fd in cooperative mode.** If you never call
  `dispatch_interrupts()`/`wait_interrupts()`, callbacks never fire — there is no
  background process doing it for you unless you forked one (scenario 7).
- **Forking *after* arming interrupts.** wiringPi's ISR pthreads don't survive
  `fork`, and a mutex held at fork time is left locked in the child. Fork first,
  then arm in the child that dispatches.
- **Sharing one device fd across forked processes.** An i2c/spi/serial handle
  should be used by a single process; two processes transacting on it interleave.

## API reference for these examples

| Call | Purpose |
|---|---|
| `setup()` / `setup_gpio()` | init (wiringPi / BCM numbering); once, in main |
| `pin_mode($pin, $mode)` | `0`=INPUT, `1`=OUTPUT |
| `digital_write($pin, $val)` / `digital_read($pin)` | pin I/O |
| `set_interrupt($pin, $edge, $cb [, $debounce_us])` | arm; `$cb->($edge, $ts_us)` |
| `wait_interrupts($timeout_ms)` | block until event/timeout, then dispatch |
| `dispatch_interrupts()` | non-blocking: dispatch pending events |
| `interrupt_fd()` | read fd for `select`/event loops |
| `interrupt_dropped()` | count of events dropped on a full pipe |
| `stop_interrupt($pin)` / `stop_interrupts()` | teardown |
| `INT_EDGE_FALLING` (1) / `INT_EDGE_RISING` (2) / `INT_EDGE_BOTH` (3) | edge constants |

> Names/signatures are provisional — see `isr-migration.md` for the authoritative,
> evolving definitions. For worker threads, shared state, and periodic events, see
> `threads-examples.md` (parked).
