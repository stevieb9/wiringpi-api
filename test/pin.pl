use strict;
use warnings;
use feature 'say';

use RPi::WiringPi::Constant qw(:all);
use Test::More;
use WiringPi::API qw(:all);

my $p = 18;

wiringPiSetupGpio();

pinMode($p, OUTPUT);
digitalWrite($p, HIGH);

say "m: " . get_alt($p);
say "s: " . read_pin($p);

# sleep 1;

pinMode($p, INPUT);

say "m: " . get_alt($p);
say "s: " . read_pin($p);

done_testing();
