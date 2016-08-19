use warnings;
use strict;

use Config;

use Inline (C => 'DATA', libs => '-lpthread', CLEAN_AFTER_BUILD => 0);

create_thread('blah');

print "after callback\n";

sub blah {
    print "perl callback\n";
}

__DATA__
__C__

#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

PerlInterpreter *saved;

void *wrapper(void *sub_name_ptr){
    char *sub_name = (char *)sub_name_ptr;

    PERL_SET_CONTEXT(saved);
    printf("threaded ok, sub: %s\n", sub_name);
    {
        dSP;
        PUSHMARK(SP);
        PUTBACK;

        for (;;){
            if (access("lock", F_OK) != -1){
                call_pv(sub_name, G_DISCARD|G_NOARGS);
            }
            else {
                printf("no trigger\n");
            }
            sleep(3);
        }
        FREETMPS;
        LEAVE;
    }
}

int create_thread(char *subname){   
    // this is what fixed things...

    saved = Perl_get_context();

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
