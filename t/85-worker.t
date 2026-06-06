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

done_testing();
