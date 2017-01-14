use warnings;
use strict;
use feature 'say';

use Time::HiRes qw(usleep);
use WiringPi::API qw(:all);

# script to blink all 8 shift register pins

my $rand;

if ($ARGV[0]){
    $rand = 1;
}

my $c = 1;

$SIG{INT} = sub {
    $c = 0;
};

setup_gpio();

my $data   = 5;
my $clk    = 6;
my $latch = 13;

shift_reg_setup(100, 8, $data, $clk, $latch);

#for (0..8){
#    my $pin = 100 + $_;
#    pin_mode($pin, 1);
#    write_pin($pin, 1);
#    print "pin $pin\n";
#    # sleep 1   
#}

if ($rand){
    while ($c){
        for (int(rand(8))){
            write_pin(100 + $_, 1);
            usleep 30000;
        }
        for (int(rand(8))){
            write_pin(100 + $_, 0);
            usleep 30000;
        }
    }
}
else {
    while ($c){
        for (0..8){
            write_pin(100 + $_, 1);
            usleep 30000;
        }
        for (0..8){
            write_pin(100 + $_, 0);
            usleep 30000;
        }
    }
}
for (100..108, $data, $clk, $latch){
    write_pin($_, 0)
}

