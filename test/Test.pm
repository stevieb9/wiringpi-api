package Test;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(pause);

sub pause {
    my $t = shift;
    select(undef, undef, undef, $t);
}

1;
__END__
