use strict;
use warnings;

use WiringPi::API qw(:all);

my $fd = serial_open('/dev/ttyAMA0', 115200);
print "$fd\n";

serial_put_char($fd, 5);
my $c = serial_get_char($fd);
print "char: $c\n";

serial_puts($fd, "hello world");

my $buf = "";
my $str = serial_gets($fd, $buf, 15);

print "$str\n";
