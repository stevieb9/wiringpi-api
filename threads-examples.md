# WiringPi::API — threads & concurrency usage examples

> **⛔ PARKED — back burner.** ISR work comes first; see `isr-examples.md` and
> `isr-migration.md`. This doc collects general background-concurrency examples
> (Perl ithreads, fork workers, periodic events). It depends on the ithread-safety
> work in `threads-patch.md`, which is **on hold** until the interrupt migration
> lands. Kept for reference, not for active work.

> **Status:** illustrates a **planned/provisional** API; not implemented. Names
> and signatures may change.

## Table of contents

- [About these examples](#about-these-examples)
- [Background interrupts with ithreads](#background-interrupts-with-ithreads)
  - [1. Dedicated interrupt thread](#1-dedicated-interrupt-thread)
- [Worker threads](#worker-threads)
  - [2. A worker on its own pins](#2-a-worker-on-its-own-pins)
  - [3. Sharing state safely between threads](#3-sharing-state-safely-between-threads)
  - [4. The setup-once-in-main contract](#4-the-setup-once-in-main-contract)
  - [5. Busy main, interrupt thread, and worker](#5-busy-main-interrupt-thread-and-worker)
- [Fork-based background work](#fork-based-background-work)
  - [6. A worker via fork](#6-a-worker-via-fork)
  - [7. Periodic background tasks](#7-periodic-background-tasks)
- [Proposed convenience helpers](#proposed-convenience-helpers)
  - [8. spawn_interrupt_handler and spawn_worker](#8-spawn_interrupt_handler-and-spawn_worker)
- [Anti-patterns to avoid](#anti-patterns-to-avoid)
- [API reference for these examples](#api-reference-for-these-examples)

## About these examples

This doc covers running work **concurrently** with the main program — distinct
from reacting to interrupts (that's `isr-examples.md`). Two mechanisms appear:

- **Perl ithreads** (`use threads`): shared-interpreter-free concurrency with one
  interpreter per thread. Requires a threaded Perl build (Raspberry Pi OS ships
  one; check `perl -V:useithreads`). Share state with `:shared` + `pi_lock`.
- **`fork`**: separate processes, works on any Perl; share via IPC.

**The concurrency contract** (from the thread-safety audit, see `isr-migration.md`):
call `setup()`, `pin_mode`, and any device `*Setup` **once in the main thread/
process before spawning**; afterwards spawned contexts may freely
`digital_read`/`digital_write` on **distinct** pins; serialize shared data with
`pi_lock`/`pi_unlock`.

---

## Background interrupts with ithreads

### 1. Dedicated interrupt thread

The ithread alternative to `isr-examples.md` scenario 7 (fork). A dedicated
ithread services the interrupt fd in its **own** interpreter while main is free to
block/compute. Arm **and** dispatch inside the spawned thread.

```perl
use strict;
use warnings;
use threads;
use threads::shared;
use WiringPi::API qw(setup pin_mode set_interrupt wait_interrupts INT_EDGE_RISING);

setup();                       # ONCE, in main, before spawning
pin_mode(0, 0);                # INPUT

my $count :shared = 0;

threads->create(sub {
    set_interrupt(0, INT_EDGE_RISING, sub { lock $count; $count++ });
    wait_interrupts(1000) while 1;
})->detach;

while (1) {
    heavy_work();
    { lock $count; print "edges so far: $count\n"; }
    sleep 1;
}

sub heavy_work {
    # ... a long computation or blocking call ...
}
```

---

## Worker threads

### 2. A worker on its own pins

```perl
use strict;
use warnings;
use threads;
use WiringPi::API qw(setup pin_mode digital_write);

setup();
pin_mode(2, 1);    # OUTPUT (in main, before spawning)

threads->create(sub {
    while (1) {
        digital_write(2, 1);
        sleep 1;
        digital_write(2, 0);
        sleep 1;
    }
})->detach;

while (1) {
    # ... main's own work ...
    sleep 5;
}
```

### 3. Sharing state safely between threads

Shared data must be `:shared`; serialize access with `pi_lock`/`pi_unlock` (keys
0-3) or `threads::shared`'s `lock`.

```perl
use strict;
use warnings;
use threads;
use threads::shared;
use WiringPi::API qw(setup pin_mode digital_read pi_lock pi_unlock);

setup();
pin_mode(3, 0);    # INPUT

my $latest :shared = 0;

threads->create(sub {
    while (1) {
        my $v = digital_read(3);
        pi_lock(0);
        $latest = $v;
        pi_unlock(0);
        select(undef, undef, undef, 0.05);   # 50ms
    }
})->detach;

while (1) {
    pi_lock(0);
    my $v = $latest;
    pi_unlock(0);
    print "latest reading: $v\n";
    sleep 1;
}
```

### 4. The setup-once-in-main contract

Do all configuration up front, single-threaded; then let threads do steady-state
I/O on distinct pins. **Never** call `setup()`/`pin_mode`/device `*Setup`
concurrently (read-modify-write on shared registers).

```perl
use threads;
use WiringPi::API qw(setup pin_mode digital_write digital_read);

setup();                              # once
pin_mode(2, 1);                       # OUTPUT  — all config here, in main
pin_mode(3, 1);                       # OUTPUT
pin_mode(4, 0);                       # INPUT

threads->create(sub { digital_write(2, $_ % 2), sleep 1 for 1 .. 1e9 })->detach;
threads->create(sub { digital_write(3, $_ % 2), sleep 1 for 1 .. 1e9 })->detach;

while (1) {
    print "pin 4 = ", digital_read(4), "\n";
    sleep 1;
}
```

### 5. Busy main, interrupt thread, and worker

Everything together: main computes, one ithread handles interrupts, another drives
an output — coordinating through `:shared` state under `pi_lock`.

```perl
use strict;
use warnings;
use threads;
use threads::shared;
use WiringPi::API qw(setup pin_mode digital_write set_interrupt wait_interrupts
                     pi_lock pi_unlock INT_EDGE_RISING);

setup();                          # once, in main, before spawning
pin_mode(0, 0);                   # INPUT  (interrupt source)
pin_mode(2, 1);                   # OUTPUT (heartbeat LED)

my $events :shared = 0;

threads->create(sub {
    set_interrupt(0, INT_EDGE_RISING, sub { pi_lock(0); $events++; pi_unlock(0) });
    wait_interrupts(1000) while 1;
})->detach;

threads->create(sub {
    while (1) {
        digital_write(2, 1);
        select(undef, undef, undef, 0.25);
        digital_write(2, 0);
        select(undef, undef, undef, 0.25);
    }
})->detach;

while (1) {
    pi_lock(0);
    my $n = $events;
    pi_unlock(0);
    print "edges seen: $n\n";
    sleep 2;
}
```

---

## Fork-based background work

(`fork` needs no threaded Perl. For fork-based *interrupt* handling specifically,
see `isr-examples.md` scenario 7.)

### 6. A worker via fork

```perl
use strict;
use warnings;
use WiringPi::API qw(setup pin_mode digital_write);

setup();
pin_mode(2, 1);                          # OUTPUT — before fork

my $pid = fork // die "fork: $!";

if ($pid == 0) {
    while (1) {                          # child: heartbeat forever
        digital_write(2, 1);
        sleep 1;
        digital_write(2, 0);
        sleep 1;
    }
    exit 0;
}

while (1) {
    # ... parent's own work ...
    sleep 5;
}

# on shutdown: kill 'TERM', $pid; waitpid $pid, 0;
```

You reap the child yourself (`waitpid` or a `$SIG{CHLD}` handler), and passing
data back to the parent needs IPC — there are no shared variables across a fork.

### 7. Periodic background tasks

For *periodic* work (poll a sensor, blink, telemetry) the fork + IPC + lifecycle
plumbing is what `Async::Event::Interval` (a fork-based CPAN module) packages up —
including crash detection/restart and a shared scalar for the latest value:

```perl
use strict;
use warnings;
use Async::Event::Interval;
use WiringPi::API qw(setup pin_mode digital_read);

setup();
pin_mode(3, 0);                              # INPUT — before the event forks

my $event  = Async::Event::Interval->new(1, \&sample);   # forks; runs every 1s
my $latest = $event->shared_scalar;
$event->start;

while (1) {
    print "latest: ", (defined $$latest ? $$latest : 'n/a'), "\n";
    $event->restart if $event->error;        # auto-recover a crashed sampler
    sleep 2;
}

sub sample {
    $$latest = digital_read(3);
}
```

**Good fit / bad fit — honestly:** this is a *timer* with **latest-value (lossy)**
shared state. Ideal for periodic sampling, wrong for **edge interrupts** (you must
not drop edges — keep those on the self-pipe, `isr-examples.md`). Note
`Async::Event::Interval` sets `$SIG{CHLD} = 'IGNORE'` and uses SysV shared memory
at load time, so it does not compose with a hand-rolled `fork`/`waitpid`.

---

## Proposed convenience helpers

### 8. spawn_interrupt_handler and spawn_worker

> **Proposed (Backlog in `threads-patch.md`)** — not specced/built. Would hide the
> `threads->create` + arm + loop boilerplate. You still write `use threads;` (it
> must load early); nothing else.

```perl
use threads;
use WiringPi::API qw(setup pin_mode spawn_interrupt_handler spawn_worker INT_EDGE_RISING);

setup();
pin_mode(0, 0);

my $h = spawn_interrupt_handler(0, INT_EDGE_RISING, \&on_edge);  # spawns + arms + loops
my $w = spawn_worker(sub { ... });                              # spawns a worker

# ... later ...
$h->stop;
$w->stop;

sub on_edge {
    print "edge\n";
}
```

## Anti-patterns to avoid

- **Registering a callback in one thread and dispatching in another.** Arm
  (`set_interrupt`) and dispatch (`wait_interrupts`) in the **same** thread — the
  callback table lives in that interpreter.
- **Concurrent `pin_mode` / `setup` / device `*Setup`.** Read-modify-write on
  shared registers; do them once, in main, before spawning. Only
  `digital_read`/`digital_write` on distinct pins are safe concurrently.
- **Touching shared Perl data without a lock.** Guard `:shared` variables with
  `pi_lock`/`pi_unlock` (or `lock`). A bare `$shared++` from two threads races.
- **Loading `use threads` late.** It must be near the top of your program, before
  other modules — loading it lazily/after other code is unreliable.
- **Mixing a hand-rolled `fork`/`waitpid` with `Async::Event::Interval`.** It sets
  `$SIG{CHLD} = 'IGNORE'` at load, which auto-reaps children — your own `waitpid`
  then fails. Pick one process-management model.

## API reference for these examples

| Call | Purpose | Needs threads? |
|---|---|---|
| `pi_lock($key)` / `pi_unlock($key)` | mutex (keys 0-3) for shared state | no (used with threads) |
| `spawn_interrupt_handler(...)` / `spawn_worker(...)` | **proposed** convenience wrappers | yes |
| `fork` (core) + a pipe / `IO::Select` | background concurrency on any Perl | no |
| `Async::Event::Interval` | fork-based **periodic** tasks; not edge interrupts | no |

> The interrupt calls (`set_interrupt`, `wait_interrupts`, `interrupt_fd`, …) are
> documented in `isr-examples.md`. Names/signatures provisional — see
> `threads-patch.md` (parked) and `isr-migration.md`.
