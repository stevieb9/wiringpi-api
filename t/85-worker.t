use strict;
use warnings;

use Test::More;
use Time::HiRes qw(usleep);

use WiringPi::API qw(worker);

# worker() runs arbitrary Perl in a forked child - none of these cases touch
# GPIO, so the whole file runs off-Pi.

# ---------------------------------------------------------------------------
# Argument validation: everything croaks BEFORE any fork.
# ---------------------------------------------------------------------------

eval { worker() };
like($@, qr/CODE reference/, 'worker() with no body croaks');

eval { worker("notcode") };
like($@, qr/CODE reference/, 'worker() with a non-CODE body croaks');

eval { worker(sub { 1 }, "notahash") };
like($@, qr/hash reference/, 'worker() with non-HASH opts croaks');

eval { worker(sub { 1 }, { interval => "soon" }) };
like($@, qr/interval/, 'worker() with non-numeric interval croaks');

eval { worker(sub { 1 }, { interval => 0 }) };
like($@, qr/interval/, 'worker() with zero interval croaks');

eval { worker(sub { 1 }, { interval => -2 }) };
like($@, qr/interval/, 'worker() with negative interval croaks');

# ---------------------------------------------------------------------------
# Construction + lifecycle: pid / running / idempotent stop.
# ---------------------------------------------------------------------------

{
    my $w = worker(sub { usleep 20_000 });
    isa_ok($w, 'WiringPi::API::Worker', 'handle');
    ok($w->pid > 0,  'pid() is a real pid');
    ok($w->running,  'running() true while alive');

    ok($w->stop,     'stop() returns true');
    ok($w->stop,     'stop() is idempotent');
    ok(! $w->running, 'running() false after stop');
}

# ---------------------------------------------------------------------------
# Reaping: an explicitly stopped child leaves no zombie.
# ---------------------------------------------------------------------------

{
    my $w   = worker(sub { usleep 20_000 });
    my $pid = $w->pid;
    $w->stop;
    is(waitpid($pid, 1), -1, 'stopped child already reaped (no zombie)');  # WNOHANG
}

# ---------------------------------------------------------------------------
# {results => 1}: every defined return value streams back, length-framed.
# ---------------------------------------------------------------------------

{
    my $i = 0;
    my $w = worker(
        sub { my $n = $i++; usleep 5_000; return $n; },
        { results => 1 },
    );

    isa_ok($w->fh, 'GLOB', 'results fh()');

    my @got;
    for (1 .. 50) {
        last if @got >= 5;
        my $v = $w->read;
        if (defined $v) {
            push @got, $v;
            next;
        }
        usleep 5_000;
    }
    $w->stop;

    ok(@got >= 3, 'results channel streamed several values') or diag "got: @got";
    is_deeply([@got[0 .. 2]], [0, 1, 2], 'streamed values arrive in order');
}

# ---------------------------------------------------------------------------
# {shared => 1}: value() returns the latest value (lossy), and caches it.
# ---------------------------------------------------------------------------

{
    my $i = 0;
    my $w = worker(
        sub { my $n = $i++; usleep 5_000; return $n; },
        { shared => 1 },
    );

    # Let the child publish a handful of updates, then stop it so no further
    # writes can race the assertions below.
    usleep 60_000;
    $w->stop;

    my $latest = $w->value;     # drains everything pending, caches the last
    ok(defined $latest, 'value() returned a latest value');
    ok($latest > 0, 'value() advanced past the first update (lossy latest)')
        or diag "latest: $latest";

    # With nothing new pending, value() returns the cached latest.
    is($w->value, $latest, 'value() caches the last seen value');
}

# ---------------------------------------------------------------------------
# value() / read() are undef when their channel was not requested.
# ---------------------------------------------------------------------------

{
    my $w = worker(sub { usleep 20_000 });
    is($w->value, undef, 'value() is undef without {shared}');
    is($w->read,  undef, 'read() is undef without {results}');
    is($w->fh,    undef, 'fh() is undef without {results}');
    $w->stop;
}

# ---------------------------------------------------------------------------
# {once => 1}: body runs exactly once, then the child exits on its own.
# ---------------------------------------------------------------------------

{
    my $i = 0;
    my $w = worker(
        sub { $i++; return $i; },
        { once => 1, results => 1 },
    );

    # The child exits after one pass; wait for running() to reflect that.
    my $exited;
    for (1 .. 200) {
        if (! $w->running) {
            $exited = 1;
            last;
        }
        usleep 5_000;
    }
    ok($exited, '{once} child exits on its own');
    ok(! $w->running, '{once} running() is false after the single pass');

    # Exactly one value was produced.
    my @got;
    while (defined(my $v = $w->read)) {
        push @got, $v;
    }
    is_deeply(\@got, [1], '{once} body ran exactly once');

    $w->stop;   # idempotent on an already-exited child
}

# ---------------------------------------------------------------------------
# {interval => $secs}: the helper paces the loop; the body carries no sleep.
# ---------------------------------------------------------------------------

{
    my $i = 0;
    my $w = worker(
        sub { my $n = $i++; return $n; },
        { interval => 0.05, results => 1 },
    );

    # Over ~0.5s at a 50ms cadence we expect roughly 10 passes - assert a loose
    # window so the test is timing-tolerant but still proves pacing happened
    # (without pacing, an empty body would spin thousands of times).
    usleep 500_000;
    $w->stop;

    my @got;
    while (defined(my $v = $w->read)) {
        push @got, $v;
    }

    ok(@got >= 3,  'interval worker produced several passes') or diag "n=" . @got;
    ok(@got <= 40, 'interval paced the loop (not a busy spin)') or diag "n=" . @got;
    is_deeply([@got[0 .. 2]], [0, 1, 2], 'interval passes arrive in order');
}

done_testing();
