# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl RPi-WiringPi-Core.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Data::Dumper;
use Test::More;
BEGIN { use_ok('RPi::WiringPi::Core') };

my $mod = 'RPi::WiringPi::Core';

my %map;

for (0..63){
    $map{$_} = RPi::WiringPi::Core::phys_to_wpi($_);
}

is $map{40}, 29, "phys pin 40 == wpi 29";
is $map{0},  -1, "phys pin 0 is -1";
is $map{2},  -1, "phys pin 2 is -1";
is $map{8},  15, "phys pin 8 == wpi 15";
is $map{16},  4, "phys pin 16 == wpi 4";

done_testing();
