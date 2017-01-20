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

my $p = 18;
my $b = 100;

wiringPiSetupGpio();
ads1115_setup($b, 0x48);

pin_mode($p, PWM_OUT);

pwm_write($p, 0);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
is analog_read($b) < 1, 1, "pwm at 0 in ok range";

pwm_write($p, 512);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
is analog_read($b) > 12000 && analog_read($b) < 14000, 1, "pwm at 512 in ok range";

pwm_write($p, 768);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
is analog_read($b) > 19000 && analog_read($b) < 21000, 1, "pwm at 768 in ok range";

pwm_write($p, 1023);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
is analog_read($b) > 98, 1, "pwm at 1023 in ok range";

pwm_set_range(9);

pwm_write($p, 5);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
is analog_read($b) > 12500 && analog_read($b) < 15500, 1, "pwm_range(9): pwm at 4 ok";

pinMode($p, OUTPUT);
write_pin($p, LOW);

# sleep hackery
select undef, undef, undef, 0.5;

is get_alt($p), OUTPUT, "pin back to OUTPUT mode ok";
is read_pin($p), LOW, "pin back to LOW state ok";
is analog_read($b) < 1, 1, "pin is not outputting any signal ok";

pwm_set_range(1023);

done_testing();
