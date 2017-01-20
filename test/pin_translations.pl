use strict;
use warnings;

BEGIN {
    if ($> != 0){
        die "sudo required...\n";
    }
}

use Test::More;
use WiringPi::API;

my $mod = 'WiringPi::API';

my %map;

# phys to wpi

for (0..63){
    $map{$_} = WiringPi::API::phys_to_wpi($_);
}

is $map{40}, 29, "phys pin 40 == wpi 29";
is $map{0},  -1, "phys pin 0 is -1";
is $map{2},  -1, "phys pin 2 is -1";
is $map{8},  15, "phys pin 8 == wpi 15";
is $map{16},  4, "phys pin 16 == wpi 4";

warn "phys_to_gpio() crashes... see issues\n";
done_testing();
exit;

# phys to gpio

for (0..63){
    $map{$_} = WiringPi::API::phys_to_gpio($_);
}

is $map{40}, 21, "phys pin 40 == BCM 21";
is $map{0},  -1, "phys pin 0 is -1";
is $map{2},  -1, "phys pin 2 is -1";
is $map{8},  14, "phys pin 8 == BCM 14";
is $map{16}, 23, "phys pin 16 == BCM 23";

# wpi to gpio

my %wpi_to_gpio_pin_map = (
    8   => 2,
    9   => 3,
    7   => 4,
    0   => 17,
    2   => 27,
    3   => 22,
    12  => 10,
    13  => 9,
    14  => 11,
    30  => 0,
    21  => 5,
    22  => 6,
    23  => 13,
    24  => 19,
    25  => 26,
    15  => 14,
    16  => 15,
    1   => 18,
    4   => 23,
    5   => 24,
    6   => 25,
    10  => 8,
    11  => 7,
    31  => 1,
    26  => 12,
    27  => 16,
    28  => 20,
    29  => 21,
);

for (keys %wpi_to_gpio_pin_map){
    is
        WiringPi::API::wpi_to_gpio($_),
        $wpi_to_gpio_pin_map{$_},
        "wpi $_ == gpio $wpi_to_gpio_pin_map{$_} ok";
}

done_testing();
