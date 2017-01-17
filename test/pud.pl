use strict;
use warnings;
use feature 'say';

use RPi::WiringPi::Constant qw(:all);
use Test::More;
use WiringPi::API qw(:all);

my $p = 18;

setup_gpio();

pin_mode($p, PWM);
is get_alt($p), PWM, "pud pin is PWM mode ok";

pull_up_down($p, PUD_UP);
is read_pin($p), HIGH, "pud UP is HIGH";

pull_up_down($p, PUD_DOWN);
is read_pin($p), LOW, "pud DOWN is LOW";

pull_up_down($p, PUD_OFF);
is get_alt($p), INPUT, "pud pin is INPUT mode ok after disabling PUD";
is read_pin($p), LOW, "pud OFF is LOW";

done_testing();

