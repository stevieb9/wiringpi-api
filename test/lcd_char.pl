use warnings;
use strict;

use WiringPi::API qw(:all);

lcdCharDef(1, 1, pack "V0C*", (1,2,3));
