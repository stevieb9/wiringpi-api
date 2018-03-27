use warnings;
use strict;

use version;

my $min_wpi_ver = 2.36;

if (! -f '/usr/include/wiringPi.h' && ! -f '/usr/local/include/wiringPi.h'){
    print "wiringPi is not installed, exiting...\n";
    exit;
}

if (my $path = (grep { -x "$_/gpio" } split /:/, $ENV{PATH})[0]){
    my $bin = "$path/gpio";
    my $gpio_info = `$bin -v`;

    if (my ($version) = $gpio_info =~ /version:\s+(\d+\.\d+)/){

        my $installed_ver = version->parse($version);

        if ($installed_ver < $min_wpi_ver){
            print "\nyou must have wiringPi version $min_wpi_ver" .
                  " or greater installed to continue.\n\n" .
                  "You have version $version\n";
            exit;
        }
    }
}
