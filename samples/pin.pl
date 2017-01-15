#!/usr/bin/perl
use strict;
use warnings;
use feature 'say';


use WiringPi::API qw(:all);
use RPi::WiringPi::Constant qw(:all);

wiringPiSetupGpio();

pinMode(29, OUTPUT);
digitalWrite(29, HIGH);
say read_pin(29);

