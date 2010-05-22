use strict;
use v5.10.0;

package MySQL::Backend::Base;
use parent 'FusqlFS::Backend::Base';

sub dsn
{
    my $self = shift;
    return 'mysql:'.$self->SUPER::dsn(@_);
}

sub init
{
    my $self = shift;
    $self->{subpackages} = {
    };
}

1;

