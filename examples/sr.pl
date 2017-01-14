use warnings;
use strict;
use feature 'say';

use WiringPi::API qw(:all);

my $c;

$SIG{INT} = sub {
    $c = 1;
};

setup_gpio();

my $data   = 5;
my $clk    = 6;
my $latch = 13;

shift_reg_setup(100, 4, $data, $clk, $latch);

for (0..3){
    my $pin = 100 + $_;
    pin_mode($pin, 1);
    write_pin($pin, 1);
    print "pin $pin\n";
    sleep 1   
}

for (0..3){
    write_pin(100 + $_, 0);
}
for ($data, $clk, $latch){
    pin_mode($_, 0);
}

