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

my $d = [0, 0, 0, 0];

my @ret = spi_data(0, $d, 4);

say $_ for @ret;

