#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use WiringPi::API qw(:all);
use RPi::WiringPi::Constant qw(:all);

{ # gpio
    
    my $p = 18;

    wiringPiSetupGpio();

    pin_mode($p, OUTPUT);
    write_pin($p, HIGH);

    is get_alt($p), 1, "gpio mode output ok";
    is read_pin($p), 1, "gpio high ok";

    pinMode($p, INPUT);

    is get_alt($p), 0, "gpio mode input ok";
    is read_pin($p), 0, "gpio low ok";
}

{ # wpi

    my $p = 5;

    wiringPiSetup();

    pin_mode($p, OUTPUT);
    write_pin($p, HIGH);

    is get_alt($p), 1, "wpi mode output ok";
    is read_pin($p), 1, "wpi high ok";

    pinMode($p, INPUT);

    is get_alt($p), 0, "wpi mode input ok";
    is read_pin($p), 0, "wpi low ok";
}

{ # phys

    my $p = 12;

    wiringPiSetupPhys();

    pin_mode($p, OUTPUT);
    write_pin($p, HIGH);

    is get_alt($p), 1, "phys mode output ok";
    is read_pin($p), 1, "phys high ok";

    pinMode($p, INPUT);

    is get_alt($p), 0, "phys mode input ok";
    is read_pin($p), 0, "phys low ok";
}

{ # sys

    my $p = 18;

    wiringPiSetupSys();

    pin_mode($p, OUTPUT);
    write_pin($p, HIGH);

    is get_alt($p), 1, "sys mode output ok";
    is read_pin($p), 1, "sys high ok";

    pinMode($p, INPUT);

    is get_alt($p), 0, "sys mode input ok";
    is read_pin($p), 0, "sys low ok";
}

done_testing();
