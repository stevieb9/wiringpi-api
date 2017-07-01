use strict;
use warnings;

use WiringPi::API qw(:all);

my $fd = serial_open('/dev/ttyS4', 9600);

my $str = serial_gets($fd, "ab", 2);

print $str;
