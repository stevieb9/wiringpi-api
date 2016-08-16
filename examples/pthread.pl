use warnings;
use strict;

use Config;

use Inline (C => 'DATA', libs => '-lpthread');

create_thread('blah');

sub blah {
    print "perl callback\n";
}

__DATA__
__C__

#include <stdio.h>
#include <pthread.h>

PerlInterpreter *saved;

void wrapper(void *sub_name_ptr){
    char *sub_name = (char *)sub_name_ptr;
    PERL_SET_CONTEXT(saved);
    printf("threaded ok, sub: %s\n", sub_name);
    dSP;
    PUSHMARK(SP);
    PUTBACK;

    call_pv(sub_name, G_DISCARD|G_NOARGS);
    FREETMPS;
    LEAVE;

    return NULL;
}

int create_thread(char *subname){   
    pthread_t sub_thread;
 
   
    if(pthread_create(&sub_thread, NULL, wrapper, subname)) {
        fprintf(stderr, "Error creating thread\n");
        return 1;
    }
    
    if(pthread_join(sub_thread, NULL)) {
        fprintf(stderr, "Error joining thread\n");
        return 2;
    }

    return 0;
}
