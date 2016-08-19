use warnings;
use strict;

use RPi::WiringPi::Constant qw(:all);
use WiringPi::API qw(:perl);

my $c = 1;
$SIG{INT} = sub {$c=0;};

setup_gpio();
pin_mode(21, INPUT);
set_interrupt(21, EDGE_FALLING, 'handler');

my $x = 1;

while ($c){
    print $x++ ."\n";
    sleep 1;
}

sub handler {
    print "pin 21 edge fall callback...\n";
}

