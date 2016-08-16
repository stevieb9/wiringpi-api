use strict;
use warnings;

use Test::More;
use RPi::WiringPi::Core;

my $mod = 'RPi::WiringPi::Core';

my %map;

if (! $ENV{PI_BOARD}){
    plan skip_all => "not a Pi board";
    exit;
}

RPi::WiringPi::Core::wiringPiSetup();

for (0..63){
    $map{$_} = RPi::WiringPi::Core::phys_to_gpio($_);
}

is $map{40}, 21, "phys pin 40 == BCM 21";
is $map{0},  -1, "phys pin 0 is -1";
is $map{2},  -1, "phys pin 2 is -1";
is $map{8},  14, "phys pin 8 == BCM 14";
is $map{16}, 23, "phys pin 16 == BCM 23";

done_testing();
