use strict;
use warnings;
use feature 'say';

BEGIN {
    if ($> != 0){
        die "sudo required...\n";
    }
}

use RPi::WiringPi::Constant qw(:all);
use Test::More;
use WiringPi::API qw(:all);

# channel /dev/spidev0.0

spi_setup(0);

my $d = [255, 254, 258];

# write a single bite; reading it back
# overwrites the TX buffer

my $ret = spiDataRW(0, $d, scalar @$d);

say("ret: $ret\n");

