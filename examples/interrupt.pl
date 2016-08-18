use warnings;
use strict;

use RPi::WiringPi;
use RPi::WiringPi::Constant qw(:all);

my $pi = RPi::WiringPi->new();
my $pin = $pi->pin(1);

WiringPi::API::set_interrupt(
    $pin->num, 
    EDGE_RISING,
    'pin_27_edge_rise'
);

$pin->pull(0);
$pin->mode(INPUT);
$pin->write(LOW);

sleep 3;

$pi->cleanup;

sub pin_27_edge_rise {
    print "pin 27 edge rise callback...\n";
    # do other stuff
}

