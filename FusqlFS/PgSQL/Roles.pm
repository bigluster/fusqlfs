use strict;
use v5.10.0;
use FusqlFS::Base;

package FusqlFS::PgSQL::Role::Permissions;
use base 'FusqlFS::Base::Interface';

sub get
{
    my $self = shift;
    my ($name) = @_;
    return {
        tables    => {},
        views     => {},
        functions => {},
    };
}

sub list
{
    return [ qw(tables views functions) ];
}

1;

package FusqlFS::PgSQL::Role::Owner;
use base 'FusqlFS::Base::Interface';

our %relkinds = qw(
    r TABLE
    i INDEX
    S SEQUENCE
);

sub new
{
    my $class = shift;
    my $relkind = shift;
    my $depth = 0+shift;
    my $self = {};

    $self->{depth} = '../' x $depth;
    $self->{get_expr} = $class->expr("SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE relname = ? AND relkind = '$relkind'");
    $self->{store_expr} = "ALTER $relkinds{$relkind} \"%s\" OWNER TO \"%s\"";

    bless $self, $class;
}

sub get
{
    my $self = shift;
    my $name = pop;
    my $owner = $self->all_col($self->{get_expr}, $name);
    return \"$self->{depth}roles/$owner->[0]" if $owner;
}

sub store
{
    my $self = shift;
    my $data = pop;
    my $name = pop;
    $data = $$data if ref $data eq 'SCALAR';
    return if ref $data || $data !~ m#^$self->{depth}roles/([^/]+)$#;
    $self->do($self->{store_expr}, [$name, $1]);
}

1;

package FusqlFS::PgSQL::Role::Owned;
use base 'FusqlFS::Base::Interface';

1;

package FusqlFS::PgSQL::Roles;
use base 'FusqlFS::Base::Interface';
use DBI qw(:sql_types);

sub new
{
    my $class = shift;
    my $self = {};

    $self->{list_expr} = $class->expr("SELECT rolname FROM pg_catalog.pg_roles");
    $self->{get_expr} = $class->expr("SELECT rolcanlogin AS can_login, rolcatupdate AS cat_update, rolconfig AS config,
            rolconnlimit AS conn_limit, rolcreatedb AS create_db, rolcreaterole AS create_role, rolinherit AS inherit,
            rolsuper AS superuser, rolvaliduntil AS valid_until
        FROM pg_catalog.pg_roles WHERE rolname = ?");

    $self->{rename_expr} = 'ALTER ROLE "%s" RENAME TO "%s"';
    $self->{drop_expr} = 'DROP ROLE "%s"';

    bless $self, $class;
}

sub get
{
    my $self = shift;
    my ($name) = @_;
    return $self->dump($self->one_row($self->{get_expr}, $name));
}

sub list
{
    my $self = shift;
    return $self->all_col($self->{list_expr})||[];
}

sub rename
{
    my $self = shift;
    my ($name, $newname) = @_;
    $self->do($self->{rename_expr}, [$name, $newname]);
}

sub drop
{
    my $self = shift;
    my ($name) = @_;
    $self->do($self->{drop_expr}, [$name]);
}

sub store
{
    my $self = shift;
    my ($name, $data) = @_;
    my $data = $self->load($data);
    my $sql = "ALTER ROLE \"$name\" ";

    my %options = qw(
        superuser   SUPERUSER
        create_db   CREATEDB
        create_role CREATEROLE
        inherit     INHERIT
        can_login   LOGIN
    );

    my %params = (
        conn_limit  => ['CONNECTION LIMIT', SQL_INTEGER],
        valid_until => ['VALID UNTIL', SQL_TIMESTAMP],
        password    => ['PASSWORD', SQL_VARCHAR],
    );

    foreach (keys %options)
    {
        next unless exists $data->{$_};
        $sql .= 'NO' unless $data->{$_};
        $sql .= $options{$_}.' ';
    }

    my @binds;
    my @types;
    foreach (keys %params)
    {
        next unless exists $data->{$_};
        $sql .= $params{$_}->[0].' ? ';
        push @binds, $data->{$_};
        push @types, $params{$_}->[1];
    }

    say STDERR $sql;
    my $sth = $self->expr($sql);
    foreach (0..$#binds)
    {
        $sth->bind_param($_+1, $binds[$_], $types[$_]);
    }
    $sth->execute();
}

1;

