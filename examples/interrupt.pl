use warnings;
use strict;

use RPi::WiringPi;
use RPi::WiringPi::Constant qw(:all);

my $pi = RPi::WiringPi->new();
my $pin = $pi->pin(27);

WiringPi::API::set_interrupt(
    $pin->num, 
    EDGE_RISING, 
    'pin_27_edge_rise'
);

$pin->mode(INPUT);

sleep 10;

$pi->cleanup;

sub pin_27_edge_rise {
    print "pin 27 edge rise callback...\n";
    # do other stuff
}

