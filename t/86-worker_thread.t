use strict;
use warnings;

use Config;
use Test::More;

# Thread mode needs an ithread-enabled Perl. Decide before 'use threads' is
# compiled: plan skip_all exits the BEGIN, so the 'use threads' below never runs
# on a non-threaded build (where it would fail to compile).
BEGIN {
    plan skip_all => 'this Perl is not built with ithreads'
        unless $Config{useithreads};
}

use threads;

use WiringPi::API qw(worker);

# A thread worker has no pipe channels: worker() rejects {results}/{shared} under
# {mechanism => 'thread'}, so read()/fh()/value() have nothing to return. They
# must croak with a guiding message (consistent with the BackgroundInterrupts
# sibling), NOT silently return undef.

my $w = worker(sub { select(undef, undef, undef, 0.05) },
    { mechanism => 'thread' });

isa_ok($w, 'WiringPi::API::WorkerThread', 'thread worker handle');

my $re = qr/no pipe channels.*pi_lock/s;

eval { $w->read };
like($@, $re, 'read() croaks under thread mode');

eval { $w->fh };
like($@, $re, 'fh() croaks under thread mode');

eval { $w->value };
like($@, $re, 'value() croaks under thread mode');

# The croak must blame the caller's line (this file), not WorkerThread.pm.
eval { $w->read };
like($@, qr/\bat \Q$0\E line \d+/, 'croak is reported from the caller, not the module');

ok($w->stop, 'thread worker stop() returns true');
ok(! $w->running, 'running() false after stop');

done_testing();
