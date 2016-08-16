use warnings;
use strict;

use RPi::WiringPi::Core;

my $core = RPi::WiringPi::Core->new;

$core->pin_mode(1, 1);

print $core->get_alt(1);

$core->pwm_write(1, 500);

sleep 5;
