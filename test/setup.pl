#!/usr/bin/perl
use strict;
use warnings;
use feature 'say';

use Test::More;
use WiringPi::API qw(:all);
use RPi::WiringPi::Constant qw(:all);

{ # gpio
    
    my $p = 18;

    wiringPiSetupGpio();

    pinMode($p, OUTPUT);
    digitalWrite($p, HIGH);

    is get_alt($p), 1, "gpio mode output ok";
    is read_pin($p), 1, "gpio high ok";

    pinMode($p, INPUT);

    is get_alt($p), 0, "gpio mode input ok";
    is read_pin($p), 0, "gpio low ok";
}

done_testing();
