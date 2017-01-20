use strict;
use warnings;
use feature 'say';

BEGIN {
    if ($> != 0){
        die "sudo required...\n";
    }
}

use RPi::ADC::ADS;
use RPi::WiringPi::Constant qw(:all);
use WiringPi::API qw(:all);

