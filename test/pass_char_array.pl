use warnings;
use strict;

use Inline 'C';

my @chars = qw(0 1 2 3 4 5 6 7);

my $packed = pack "V0C*", @chars;

chardef($packed);

__END__
__C__

#include <stdio.h>

void chardef (unsigned char* data){
    int i;
    for (i=0; i<8; i++){
       printf("%d\n", (int)data[i]);
    }
}

