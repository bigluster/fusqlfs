use strict;
use 5.010;

package FusqlFS::Backend::MySQL::Procedures;
use FusqlFS::Version;
our $VERSION = $FusqlFS::Version::VERSION;
use parent 'FusqlFS::Artifact';

=head1 NAME

FusqlFS::Backend::MySQL::Procedures - FusqlFS MySQL database stored procedures interface

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 EXPOSED STRUCTURE

=over

=item F<./create.sql>

C<CREATE PROCEDURE> statement to create the procedure.

=item F<./comment>

Procedure comment

=item F<./struct>

Additional stored procedure info with following fields:

=over

=item C<sql>

I<one of contains, no, reads, modifies> an SQL mode

=item C<security>

I<one of definer or invoker> security context

=item C<parameters>

List of procedure parameters.

=back

=item F<./code>

Stored procedure code.

=item F<./definer>

Symlink to user who defined the procedure.

=back

=cut

sub init
{
    my $self = shift;
    $self->{create_expr} = 'CREATE PROCEDURE `%(name)$s` (%(params)$s) %(sql_mode)$s SQL SECURITY %(security)$s %(mutable)$s DETERMINISTIC %(code)$s';
    $self->{drop_expr} = 'DROP PROCEDURE `%s`';
    $self->{list_expr} = $self->expr('SELECT name FROM mysql.proc WHERE db = DATABASE() AND type = "PROCEDURE"');
    $self->{get_expr} = $self->expr('SELECT * FROM mysql.proc WHERE db = DATABASE() AND type = "PROCEDURE" AND name = ?');
    $self->{get_create_expr} = 'SHOW CREATE PROCEDURE `%s`';
}

sub drop
{
    my $self = shift;
    my $name = shift;
    $self->do($self->{drop_expr}, [$name]);
}

sub create
{
    my $self = shift;
    $self->store($_[0], {
        struct => {
            sql        => 'contains',
            security   => 'definer',
            immutable  => 'yes',
            parameters => [],
        },
        code => 'BEGIN SELECT 1; END',
        definer => \('users/' . $self->dbh()->{Username} . '@%'),
        comment => '',
    })
}

sub store
{
    my $self = shift;
    my ($name, $data) = @_;
    my $struct = $self->validate($data, {
        struct => {
            sql        => qr/^(?:|no|contains|reads|modifies)$/i,
            security   => qr/^(?:definer|invoker)$/i,
            immutable  => '',
            parameters => ['ARRAY', sub {
                    foreach my $v (@$_) {
                        die 'INVALID' if $v !~ /^(?:in|out)\s+\w+\s+[\w\s(),]+$/i;
                    }
                    return $_;
                }],
        },
        code => undef,
        definer => ['SCALAR', sub{ $$_ =~ m{^users/\w+} }],
        comment => undef,
    }) or return;

    my %sql_modes = {
        no       => 'NO SQL',
        contains => 'CONTAINS SQL',
        reads    => 'READS SQL DATA',
        modifies => 'MODIFIES SQL DATA',
    };

    $self->drop($name);
    $self->do($self->{create_expr}, {
        name     => $name,
        params   => join(', ', @{$struct->{struct}->{parameters}||[]}),
        sql_mode => $sql_modes{lc($struct->{struct}->{sql})} || '',
        security => uc($struct->{struct}->{security}),
        mutable  => $struct->{struct}->{immutable}? '': 'NOT',
        code     => $struct->{code},
    });
}

sub rename
{
    my $self = shift;
    my ($name, $newname) = @_;

    my $data = $self->get($name);
    $self->drop($name);
    $self->store($newname, $data);
}

sub list
{
    my $self = shift;
    return $self->all_col($self->{list_expr});
}

sub get
{
    my $self = shift;
    my $name = shift;

    my $data = $self->one_row($self->{get_expr}, $name);
    return unless $data;

    my %sql_modes = (
        NO_SQL            => 'no',
        CONTAINS_SQL      => 'contains',
        READS_SQL_DATA    => 'reads',
        MODIFIES_SQL_DATA => 'modifies',
    );

    my $param_list = $data->{param_list};
    $param_list =~ s/^\s+//;
    $param_list =~ s/\s+$//;
    $param_list =~ s/\s+/ /g;

    return {
        struct => $self->dump({
            sql        => $sql_modes{$data->{sql_data_access}},
            security   => lc($data->{security_type}),
            immutable  => $data->{is_deterministic} eq 'YES',
            parameters => [ split(', ', $param_list) ],
        }),
        code => $data->{body},
        definer => \"users/$data->{definer}",
        comment => $data->{comment},
    };
}

1;
