use strict;
use v5.10.0;

package FusqlFS::Artifact;

=head1 NAME

FusqlFS::Artifact - basic abstract class to represent database artifact in FusqlFS

=head1 SYNOPSIS

    package FusqlFS::Backend::PgSQL::Tables;
    use parent 'FusqlFS::Artifact';

    sub new
    {
        my $class = shift;
        my $self = {};

        # initialize Tables specific resources

        bless $self, $class;
    }

    sub get
    {
        my $self = shift;
        my ($table, $name) = @_;
        return $self->one_row("SELECT * FROM %s WHERE id = ?", [$table], $name);
    }

    sub list
    {
        my $self = shift;
        my ($table) = @_;
        return $self->all_col("SELECT id FROM %s %s", [$table, $self->limit]);
    }

    sub store
    {
        my $self = shift;
        my ($table, $data) = @_;
        my $row = $self->validate($data, {
                id    => qr/^\d+$/,
                -func => '',
            }) or return;

        my $func = $row->{func}? $row->{func}.'(?)': '?';
        my $sth = $self->build("UPDATE $table SET ", sub{
            my ($k, $v) = @_;
            return " WHERE " unless $k;
            return " $k = $func ", $row->{$k}, $v;
        }, %{$self->get_table_fields($table)},
           '' => '',
           id => SQL_INTEGER);

        $sth->execute();
    }

    sub get_table_fields
    {
        my $self = shift;
        my ($table) = @_;
        # fetches and returns field name => type hashref.
    }

=head1 DESCRIPTION

This abstract class declares interface between database artifacts (like tables,
data rows, functions, roles etc.) and L<Fuse> hooks in L<FusqlFS>.

The point of this class is to abstract database layer interaction from file
system structure operations, so it provides some basic operations under
database artifacts like "get", "list", "create", "drop", etc.

For example L<FusqlFS::Backend::PgSQL::Tables> subclass defines it's
L<get|FusqlFS::Backend::PgSQL::Tables/get> method to return table's description
and L<list|FusqlFS::Backend::PgSQL::Tables/list> method to list all available
tables, so this subclass is represented as directory with tables in file system.

For more examples see childrens of this class.

=head1 METHODS

=cut

our $instance;

=head2 Abstract interface methods

=begin testing Artifact

#!noinst

isa_ok FusqlFS::Artifact->new(), 'FusqlFS::Artifact';
is FusqlFS::Artifact->get(), '';
is FusqlFS::Artifact->list(), undef;
foreach my $method (qw(rename drop create store))
{
    is FusqlFS::Artifact->$method(), 1;
}

=end testing

=over

=item new

Fallback constructor, shouldn't be called at all.

Input: $class
Output: $artifact_instance.

=item get

Get item from this artifact.

Input: @names.
Output: $hashref|$arrayref|$scalarref|$coderef|$scalar|undef.

Hashrefs and arrayref are represented as directories in filesystem with keys
(or indices in case of arrayref) as filenames and values as their content
(maybe hashrefs or arrayrefs as well).

Scalarrefs are represented as symlinks, their content being the path to
referenced object in filesystem.

Coderefs provide "pseudopipes" interface: at first request referenced sub is
called without parameters for initialization and file content will be whatever
the sub returns. On any write to the "pseudopipe" the sub is called with
written data as first argument and the content of the file will be any text the
sub returns back. Dynamic DB queries in L<FusqlFS::Backend::PgSQL::Queries>
class are implemented with this interface.

Scalars are represented with plain files.

If this sub returns undef the file with given name is considered non-existant,
and user will get C<NOENT> error.

=item list

Get list of items, represented by class.

Input: @names.
Output: $arrayref|undef.

If this method returns arrayref of scalars, then the class is represented with
directory containing elements with names from this array, otherwise (the method
returns undef) the type of filesystem object is determined solely on L</get>
method call results.

=item rename

Renames given database artifact.

Input: @names, $newname.
Output: $success.

This method must rename database object defined with @names to new $newname
and return any "true" value on success or undef on failure.

=item drop

Removes given database artifact.

Input: @names.
Output: $success.

This method must drop given database object defined with @names and return
any "true" value on success or undef on failure.

=item create

Creates brand new database artifact.

Input: @names.
Output: $success.

This method must create new database object by given @name and return any
"true" value on success or undef on failure. If given object can't be created
without additional "content" data (e.g. table's index) it should create some
kind of stub in memory/cache/anywhere and this stub must be visible via L</get>
and L</list> methods giving the user a chance to fill it with some real data,
so successive L</store> call can create the object.

=item store

Stores any changes to object in database.

Input: @names, $data.
Output: $success.

This method must accept the same $data structure as provided by L</get> method,
possibly modified by user, and store it into database, maybe creating actual
database object in process (see L</create> for details).
The method must return any "true" value on success or undef on failure.

=back

=cut
sub new { bless {}, $_[0] }
sub get { return '' }
sub list { return }
sub rename { return 1 }
sub drop { return 1 }
sub create { return 1 }
sub store { return 1 }

=head2 DBI interface methods

=over

=item dbh

Returns underlayed DBI handler.

Output: $dbh.

=item expr, cexpr

Prepare expression with $dbh->prepare() or $dbh->prepare_cached().

Input: $sql, @sprintf.
Output: $sth.

If C<@sprintf> is not empty, C<$sql> must be a scalar string with
L<printf|perlfunc/sprintf FORMAT, LIST >-compatible placeholders, and
C<sprintf()> will be called to populate this string with values from
C<@sprintf> array.

The difference between C<expr> and C<cexpr> is the first calls L<DBI/prepare>
and the second calls L<DBI/prepare_cached>.

=item do, cdo

Prepare and execute expression just like L<DBI/do>.

Input: $sth, @binds or $sql, $sprintf, @binds.
Output: $result.

Both of them can take either SQL statement as a scalar string or prepared DBI
statement in place of first argument.

If the first argument is a scalar string, the second argument can be either an
arrayref or a hashref, and if it is, the string must be
L<printf|perlfunc/sprintf EXPR, LIST >-compatible format string and
L</hprintf()> will be used to populate SQL statement with values from second
argument just like with L<expr|/expr, cexpr>.

C<do> just calls L<DBI/do> and returns success value returned with it,
while C<cdo> calls L<DBI/prepare_cached> and returns this prepared statement
in case it was successfully executed, undef otherwise.

=item one_row, all_col, all_row

Executes given statement and returns well formatted result.

Input: $sth, @binds or $sql, $sprintf, @binds.
Output: $result.

Basicly these methods accept the same arguments (and process them the same way)
as L<do|/do, cdo>, but return results in format better suited for immediate
usage.

C<one_row> returns the first row as hashref with field names as keys and field
values as values. C<all_col> returns arrayref composed from first field values
from all result rows. C<all_row> returns arrayref composed from hashrefs, where
each hashref represents data row with field names as keys and field values as
values.

=back

=cut

sub dbh
{
    $instance->{dbh};
}

sub expr
{
    my ($self, $sql, @sprintf) = @_;
    $sql = sprintf($sql, @sprintf) if @sprintf;
    return $instance->{dbh}->prepare($sql);
}

sub cexpr
{
    my ($self, $sql, @sprintf) = @_;
    $sql = sprintf($sql, @sprintf) if @sprintf;
    return $instance->{dbh}->prepare_cached($sql, {}, 1);
}

sub do
{
    my ($self, $sql, @binds) = @_;
    $sql = hprintf($sql, shift @binds) if !ref($sql) && ref($binds[0]);
    $instance->{dbh}->do($sql, {}, @binds);
}

sub cdo
{
    my ($self, $sql, @binds) = @_;
    $sql = $self->cexpr($sql, !ref($sql) && ref($binds[0])? @{shift @binds}: undef);
    return $sql if $sql->execute(@binds);
}

sub one_row
{
    my ($self, $sql, @binds) = @_;
    $sql = hprintf($sql, shift @binds) if !ref($sql) && ref($binds[0]);
    return $instance->{dbh}->selectrow_hashref($sql, {}, @binds);
}

sub all_col
{
    my ($self, $sql, @binds) = @_;
    $sql = hprintf($sql, shift @binds) if !ref($sql) && ref($binds[0]);
    return $instance->{dbh}->selectcol_arrayref($sql, {}, @binds);
}

sub all_row
{
    my ($self, $sql, @binds) = @_;
    $sql = hprintf($sql, shift @binds) if !ref($sql) && ref($binds[0]);
    return $instance->{dbh}->selectall_arrayref($sql, { Slice => {} }, @binds);
}

=head2 Data manipulation methods

=over

=item load

Parses input data in configured string format (e.g. YAML, JSON or XML) and
returns perl structure (hashref or arrayref).

Input: $string_data.
Output: $parsed_data.

Uses configured parser to deserialize plain string and produce perl structure
(usually a hashref). In case of parsing failure returns undef.

If C<$string_data> is not a plain string, this method returns this value
intact, so you can call this method on input data any number of times just to
make sure they are correct perl structure, not a serialized data.

It is opposite of L</dump>.

=cut
sub load
{
    return $_[1] if ref $_[1];
    my $data;
    eval { $data = $instance->{loader}->($_[1]) };
    return if $@;
    return $data;
}

=item validate

Validates input data against a set of simple rules.

Input: $data, $rule, $overrule.
Output: $validated_data|undef.

A rule can be:

=over

=item Hashref

The input data must be a hashref, every field in from rule's hash must also
exist in data hash, rule's hash values are subrules to be matched against
data's hash values. Hash keys with minus as first char are optional.

If input data is a scalar, it will be parsed with standard loader using
L</load> method, and validation will fail if C<load()> call is.

=item Scalar

Ref of data value must be equal to this rule's value.
If undef, data value must be simple scalar.

=item Arrayref

Every element in rule's array is a subrule, data value must match
against all of the subrules.

=item Coderef

A subroutine referenced by the rule's value is called with data value
as the first argument, it should return processed data if data is correct
or undef if data is incorrect.

=item Anything else

Data's value must magically match rule's value (with C<~~> operator).

=back

Optional third argument (C<$overrule>) must be a coderef. It will be called with
$_ locally set to parsed data and must return boolean value. If this value is
false, then all data is discarded and validation fails, otherwise everything is
ok.

=cut
sub validate
{
    my $self = shift;
    my ($data, $rule, $overrule) = @_;
    return $data unless defined $rule;
    my $result;

    my $ref = ref $rule;
    if ($ref eq 'ARRAY') {
        $result = $data;
        foreach my $subrule (@$rule)
        {
            $result = $self->validate($result, $subrule);
            return unless defined $result;
        }
    } elsif ($ref eq 'CODE') {
        local $_ = $data;
        $result = $rule->();
    } elsif ($ref eq 'HASH') {
        $result = {};
        my $struct = ref $data? $data: $self->load($data);
        return unless ref $struct eq 'HASH';
        while (my ($field, $subrule) = each %$rule)
        {
            my $opt = $field =~ s/^-//;
            unless (exists $struct->{$field})
            {
                next if $opt;
                return;
            }
            return unless defined($result->{$field} = $self->validate($struct->{$field}, $subrule));
        }
    } elsif ($ref eq '') {
        return unless ref $data eq $rule;
        $result = $data;
    } else {
        return unless $data ~~ $rule;
        $result = $data;
    }

    if ($overrule)
    {
        local $_ = $result;
        return unless $overrule->($data);
    }
    return $result;
}

=item set_of

Helper validation function, creates L</validate> rule to check
if given value is a set with elements from given variants set.

Input: @variants.
Output: $rule.

=cut
sub set_of
{
    my (undef, @variants) = @_;
    return sub {
        return unless ref $_ eq 'ARRAY';
        my @items = grep $_ ~~ @variants, keys %{{ map { $_ => 1 } @$_ }};
        return \@items if scalar(@items) > 0;
    };
}

=item dump

Convert perl structure into string of configured format (e.g. YAML, JSON or
XML).

Input: $data.
Output: $string.

Uses configured dumper to serialize perl structure into plain scalar string.

It is opposite of L</load>.

=cut
sub dump
{
    return $instance->{dumper}->($_[1]) if $_[1];
    return;
}

=item asplit

Splits string using configured split character.

Input: $string.
Output: @chunks.

It is opposite of L</ajoin>.

=cut
sub asplit
{
    return split $instance->{fnsplit}, $_[1];
}

=item ajoin

Joins chunks with configured split character as a glue.

Input: @chunks.
Output: $string.

It is opposite of L</asplit>.

=cut
sub ajoin
{
    shift @_;
    return join $instance->{fnsep}, @_;
}

=item concat

Produces SQL statement to join given data chunks with configured split
character as a glue.

Input: @chunks.
Output: $sql_clause.

It is opposite of L</asplit> (in some sense).

=cut
sub concat
{
    shift @_;
    return '"' . join("\" || '$instance->{fnsep}' || \"", @_) . '"';
}

=item build

Builds SQL statement step by step from given configuration data chunks,
prepares and binds it afterwards.

Input: $sql, $filter, %iter.
Output: $sth.

C<$filter> must be a coderef, C<$sql> is a initial SQL statement value to build
upon and C<%iter> is a series of key-value pairs (normally meant to be field
value => build config pairs, but it is not carved in stone).

For every key-value pair in C<%iter> C<$filter-E<gt>($key, $value)> is called in
list context. It must return the next chunk of SQL which will be added to
resulting SQL statement and an optional bind value to be associated with this
SQL chunk. This bind value must be either a single bind value or a bind value
and a configaration parameter for L<DBI/bind_param> (i.e. third argument).
If C<$filter> returns empty list (or undef, which is the same for list context)
the iteration is silently skipped and the next pair from C<%iter> is taken.

When C<%iter> is depleted, constructed SQL statement is prepared, all gathered
bind values are bound to it using C<bind_param()> and the resulting statement
handler is returned.

So you can use this method to construct complex SQL statements using table
driven SQL statements construction, producing finely tuned binds with correctly
typed bind values.

=back

=cut
sub build
{
    my ($self, $sql, $filter, %iter) = @_;
    my (@binds, @bind);
    while (my ($field, $value) = each %iter)
    {
        next unless (@bind) = ($filter->($field, $value));
        $sql .= shift @bind;
        push @binds, [ @bind ] if @bind;
    }
    $sql = $instance->{dbh}->prepare($sql);
    $sql->bind_param($_+1, @{$binds[$_]}) foreach (0..$#binds);
    return $sql;
}

=item hprintf

I<Static method>. Extended L<sprintf|perlfunc/sprintf FORMAT, LIST > version.

Input: $format, $binds.
Output: $string.

The C<$format> is the same as for C<sprintf>, C<$binds> is either an arrayref
or a hashref. If it is an arrayref the result of the method is the same as of
C<sprintf($format, @$binds)>. If it is a hashref the result is a little
different.

For hashref C<$binds> all placeholders in C<$format> must be in the form
of C<%(key)$x>, where C<x> is any C<sprintf> compatible conversion
and C<key> is the key in the C<%$binds>, so that instead of positional
placeholders substitution, placeholders in C<$format> are substituted
with correspondent C<%$binds>' values.

E.g. if you call C<hprintf("%(msg)s: %(count)d\n", { msg =E<gt> 'The counter is',
count =E<gt> 10 })> you will get the string C<"The counter is: 10\n"> as the
result. This is really useful if you need to keep formatting strings loosely
linked with real data inserted into them, e.g. in case of l10n with something
like gettext.

=cut
sub hprintf
{
    my ($format, $vars) = @_;
    my @binds;

    if (ref $vars eq 'ARRAY')
    {
        @binds = @$vars;        
    }
    else
    {
        my $i = 0;
        @binds = map { $format =~ s/\%\($_\)\$/'%'.(++$i).'$'/ge; $vars->{$_} } keys %$vars;
    }
    return sprintf($format, @binds);
}

=head2 Configuration methods

=over

=item limit

Returns configured C<LIMIT ...> clause or empty string if it's not configured.

Output: $limit_clause.

This method can be used to compose C<SELECT ...> statements according to
configured limit option.

=cut
sub limit
{
    my $limit = $instance->{limit};
    return $limit? "LIMIT $limit": '';
}

=item fnsep

Returns configured split character.

Output: $fnsep.

=cut
sub fnsep
{
    return $instance->{fnsep};
}


1;

__END__

=back
