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

my $p = 18;

setup_gpio();

write_pin($p, INPUT);
pin_mode($p, OUTPUT);

is get_alt($p), OUTPUT, "gpio setup pin mode ok";
is read_pin($p), LOW, "gpio setup default read LOW ok";

write_pin($p, HIGH);
is read_pin($p), HIGH, "gpio setup pin HIGH ok";

pin_mode($p, INPUT);

is get_alt($p), INPUT, "gpio setup pin mode back to INPUT ok";

pause(0.3);

is read_pin($p), LOW, "gpio setup back to INPUT, LOW ok";

done_testing();

