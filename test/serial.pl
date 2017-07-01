use strict;
use warnings;

use WiringPi::API qw(:all);

my $fd = serial_open('/dev/ttyS4', 9600);

print $fd;
