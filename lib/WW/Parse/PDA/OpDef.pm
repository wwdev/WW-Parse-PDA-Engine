package WW::Parse::PDA::OpDef;
use feature qw(:5.12);
use strict;

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

