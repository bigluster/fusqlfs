use strict;
use 5.010;

package FusqlFS::Backend::MySQL;
our $VERSION = "0.005";
use parent 'FusqlFS::Backend::Base';

use FusqlFS::Backend::MySQL::Tables;
use FusqlFS::Backend::MySQL::Users;

sub init
{
    my $self = shift;
    $self->{subpackages} = {
        tables => new FusqlFS::Backend::MySQL::Tables(),
        users  => new FusqlFS::Backend::MySQL::Users(),
    };
}

sub dsn
{
    my $self = shift;
    return 'mysql:'.$self->SUPER::dsn(@_);
}

1;

