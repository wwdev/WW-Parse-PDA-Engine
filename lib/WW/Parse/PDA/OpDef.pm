package WW::Parse::PDA::OpDef;
use feature qw(:5.12);
use strict;

=pod

=head1 NAME

WW::Parse::PDA::OpDef - Parsing Op Definition

=head1 DESCRIPTION

This class describes a parsing op.

=head1 ATTRIBUTES

=head2 op_type - string

The name/type of the parsing op.

=head2 is_custom_op - boolean

This boolean indicates whether the op being described is a standard
parsing op.

=head2 op_func - code ref: sub($$$) { my ($ctx, $op_index, $op_list) }

This is the code ref for the op implementation. All parsing ops must reset the
parsing position when they fail (set C<< $ctx->{match_status} >> to undef). The 
return value of an op is the next op's index. A sequential op will return the
passed in index + 1 + the count of it's C<< $op_list >> arguments.

The parse position is stored in the regex value read and set by the 
C<< pos() >> function for the text value C<< ${ $ctx->text_ref } >>. 
Ops must not modify the text being parsed or change what string 
C<< $ctx->text_ref >> references.

The op's code ref will be passed these arguments:

=over 4

=item $ctx - instance of WW::Parse::PDA::ExecCtx

This is the parsing context defining the PDA state.

=item $op_index - int index

This is the start index in C<< $op_list >> for the op and
its iC<< $op_list >> arguments. For example, the test_match op
takes two C<< $op_list >> arguments: the index for the ok op,
and the index for the fail op. In the C<< $op_list >> array this
this looks like:

    $op_list[$op_index]         - code ref for the op
    $op_list[$op_index+1]       - int (ok op index)
    $op_list[$op_index+2]       - int (fail op index)

The op would return either C<< $op_list->[$op_index+1] >> or
C<< $op_list->[$op_index+2] >>.

=item $op_list - array ref

This is the array containing all of the parsing ops for every rule.
Op indices always point to an op code ref. The array values after
the code ref are the C<< $op_list >> arguments.

=back

=head2 arg_names - array ref of strings

This array contains the name of the C<< $op_list >> arguments.

=head2 arg_types - array ref of strings

This array contains type specifiers for the C<< $op_list >> arguments.
It must be the same length as C<< arg_names >>. Look in C<< WW::Parse::PDA::OpDefs >>
for the use of the type specfiers.

=head2 trace_flags - int

This is a bit mask defining when an op is displayed during tracing. It is
bit-anded with the context's trace flags to test for a non-zero value.

=head1 CUSTOM OPS

Grammar-defined parse ops always have exactly one C<< $op_list >> argument:
an array with values defined in the grammar. So custom ops should
always return C<< $op_index + 2 >>,

=head1 COPYRIGHT

Copyright (c) 2013 by Lee Woodworth. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

use Moose;

has op_type => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
);

has is_custom_op => (
    is          => 'ro',
    isa         => 'Bool',
);

has op_func => (
    is          => 'ro',
    required    => 1,
);

has arg_names => (
    is          => 'ro',
    isa         => 'ArrayRef[Str]',
);

has arg_types => (
    is          => 'ro',
    isa         => 'ArrayRef[Str]',
);

has trace_flags => (
    is          => 'ro',
    isa         => 'Int',
    writer      => 'set_trace_flags',
    default     => 0,
);

sub BUILD {
    my ($self, $args) = @_;
    my $arg_types = $self->arg_types;
    unless ($arg_types && @$arg_types) {
        $self->{arg_types} = undef;
        $self->{arg_names} = undef;
        return;
    }

    my $arg_names = $self->arg_names;
    die ("names/types mismatch")
        unless $arg_names && scalar (@$arg_types) == scalar (@$arg_names);
}

no Moose;
__PACKAGE__->meta->make_immutable;

sub num_args {
    my $types = $_[0]->{arg_types};
    return $types ? scalar (@$types) : 0;
}

#sub is_jump_op {
#    my ($self) = @_;
#    my $arg_types = $self->arg_types;
#    return $arg_types && grep { $_ eq 'OpIndex' } @$arg_types;
#}

sub check_args {
    my ($self, $args) = @_;
    my $arg_types = $self->arg_types;
    if ($arg_types) {
        die ("arg_type/arg count mismatch for " . $self->op_type)
            unless $args && scalar (@$args) == scalar (@$arg_types);
    }
    elsif ($args) {
        die $self->op_type . ' takes no args';
    }
}

sub scan_args {
    my ($self, $args, $sub_ref) = @_;
    my $arg_types = $self->arg_types;
    my $arg_names = $self->arg_names;
    return unless $arg_types;

    for (my $i=0; $i<@$arg_types; $i++) {
        $sub_ref->($i, $args, $arg_types->[$i], $arg_names->[$i]);
    }
}

use overload 
    '""'        => 'to_string', 
    'bool'      => '_bool',
    fallback    => 1;

sub to_string {
    my ($self) = @_;
    my $text = $self->op_type;
    if (my $arg_types = $self->arg_types) {
        $text .= '(';
        my $arg_names = $self->arg_names;
        for (my $i=0; $i<@$arg_types; $i++) {
            $text .= ($i ? ', ' : '') . 
                $arg_names->[$i] . ': ' . $arg_types->[$i];
        }
        $text .= ')';
    }
    return $text;
}

sub _bool {
    no overloading;
    return defined ($_[0]);
}

1;

