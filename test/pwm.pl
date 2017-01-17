use strict;
use warnings;
use feature 'say';

use RPi::ADC::ADS;
use RPi::WiringPi::Constant qw(:all);
use Test::More;
use WiringPi::API qw(:all);

my $adc = RPi::ADC::ADS->new;

my $p = 18;

wiringPiSetupGpio();

pin_mode($p, PWM_OUT);

pwm_write($p, 512);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
say "UNKNOWN: " . read_pin($p);
is $adc->percent > 40 && $adc->percent < 60, 1, "pwm at 512 in ok range";

pwm_write($p, 768);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
say "UNKNOWN: " . read_pin($p);
is $adc->percent > 70 && $adc->percent < 80, 1, "pwm at 768 in ok range";

pwm_write($p, 1023);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
say "UNKNOWN: " . read_pin($p);
is $adc->percent > 98, 1, "pwm at 1023 in ok range";

pwm_range(9);

pwm_write($p, 4);

is get_alt($p), PWM_OUT, "pin is in pwm output mode ok";
say "UNKNOWN: " . read_pin($p);
is $adc->percent > 40 && $adc->percent < 60, 1, "pwm_range(9): pwm at 4 ok";

pinMode($p, INPUT);

is get_alt($p), INPUT, "pin back to INPUT mode ok";
is read_pin($p), LOW, "pin back to LOW state ok";
is $adc->volts < 1, "pin is not outputting any signal ok";

pwm_range(1023);

done_testing();
