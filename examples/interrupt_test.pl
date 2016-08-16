use warnings;
use strict;

use Inline ('C' => 'DATA', libs => '-lwiringPi');

# direct call

callback();

testing();

sub p_callback {
    print "in perl callback\n";
}

__DATA__
__C__

#include <stdlib.h>
#include <stdio.h>
#include <wiringPi.h>

void testing();
void callback();

void callback(){
   dSP;
    PUSHMARK(SP);
    PUTBACK;

    call_pv("p_callback", G_DISCARD|G_NOARGS);

    FREETMPS;
    LEAVE;         

}

void testing(){
    interruptTest(&callback);
//    wiringPiISR(23, 1, &callback);
}
