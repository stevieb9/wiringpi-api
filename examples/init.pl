use warnings;
use strict;

use RPi::WiringPi::Core;

my $core = RPi::WiringPi::Core->new;

$core->pin_mode(1, 1);
