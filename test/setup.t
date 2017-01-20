use strict;
use warnings;
use feature 'say';

BEGIN {
    if ($> != 0){
        die "sudo required...\n";
    }
}

use lib '.';
use Test qw(pause);

use RPi::WiringPi::Constant qw(:all);
use Test::More;
use WiringPi::API qw(:all);

my $p = 1;

setup();

write_pin($p, INPUT);
pin_mode($p, OUTPUT);

is get_alt($p), OUTPUT, "wpi setup pin mode ok";
is read_pin($p), LOW, "wpi setup default read LOW ok";

write_pin($p, HIGH);
is read_pin($p), HIGH, "wpi setup pin HIGH ok";

pin_mode($p, INPUT);

pause(0.5);

is get_alt($p), INPUT, "wpi setup pin mode back to INPUT ok";
is read_pin($p), LOW, "wpi setup back to INPUT, LOW ok";

done_testing();

