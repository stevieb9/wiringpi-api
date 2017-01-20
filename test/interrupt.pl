use warnings;
use strict;
use feature 'say';

use lib '.';

BEGIN {
    if ($> != 0){
        die "sudo required...\n";
    }
}

use RPi::WiringPi::Constant qw(:all);
use Test qw(pause);
use Test::More;
use WiringPi::API qw(:all);

setup_gpio();

pull_up_down(21, PUD_UP);
is read_pin(21), HIGH, "pin starts HIGH ok";

pause(0.3);

setInterrupt(21, EDGE_FALLING, 'main::handler');

pause(0.3);

pull_up_down(21, PUD_DOWN);
say read_pin(21);

pause(0.3);

pull_up_down(21, PUD_UP);
say read_pin(21);

pause(0.3);

pull_up_down(21, PUD_DOWN);
say read_pin(21);

pause(0.3);

pull_up_down(21, PUD_OFF);


BEGIN {
    sub handler {
        print "in edge fall interrupt handler...\n";
    }
}

done_testing();
