use warnings;
use strict;

use Inline 'C';

pass_to_c("hello");

sub pass_to_c {
    __cfunc(shift);
}

__END__
__C__

#include <stdio.h>

void __cfunc (const char* data){
    printf("%s\n", data);
}
