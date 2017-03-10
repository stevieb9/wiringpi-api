use warnings;
use strict;

use WiringPi::API qw(:all);

setup_gpio();

my %args = (
    cols => 16,
    rows => 2,
    bits => 4,
    rs => 23,
    strb => 16,
    d0 => 5,
    d1 => 6,
    d2 => 13, 
    d3 => 19,
    d4 => 0,
    d5 => 0, 
    d6 => 0, 
    d7 => 0,
);

my $fd = lcd_init(%args);

my $def = [
  0b11111,
  0b10001,
  0b10001,
  0b10101,
  0b11111,
  0b10001,
  0b10001,
  0b11111,
];

lcd_clear($fd);
sleep 1;

lcd_position($fd, 0, 0);

lcd_char_def($fd, 0, $def);

lcd_position($fd, 1, 0);
lcd_put_char($fd, 65);


sleep 1;

lcd_clear($fd);
