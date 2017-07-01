use strict;
use warnings;
use feature 'say';

use WiringPi::API qw(:all);

my $fd = serial_open('/dev/ttyAMA0', 115200);
print "$fd\n";

serial_put_char($fd, 5);
serial_put_char($fd, 6);

say serial_data_avail($fd);

my $c = serial_get_char($fd);
print "char: $c\n";

serial_puts($fd, "hello world");

my $str = serial_gets($fd, 11);

print "$str\n";

for (1..100){
    serial_put_char($fd, $_);
    say serial_get_char($fd);
}

