package WW::Parse::PDA::ExecCtx;
use feature qw(:5.12);
use strict;

use Moose;

has text_ref => (
    is          => 'ro',
    writer      => 'set_text_ref',
);

has global_data => (
    is          => 'ro',
    isa         => 'Ref',
);

has match_status => (
    is          => 'rw',
    isa         => 'Bool',
    default     => undef,
);

has last_match => (
    is          => 'rw',
);

has trace_handler => (
    is          => 'rw',
);

has error_message => (
    is          => 'rw',
    isa         => 'Str',
);

has [qw( LITERAL_LIST REGEX_LIST RULE_DEF_INDEXES RULE_DEF_NAMES )] => (
    is          => 'rw',
);

has [qw( temp1 temp2 )] => (
    is          => 'ro',
    init_arg    => undef,
);

has ctx_stack => (
    is          => 'ro',
    isa         => 'ArrayRef',
    default     => sub { [] }
);

# stacked state

has rule_index => (
    is          => 'rw',
    isa         => 'Int',
);

has [qw( ok_return fail_return set_match_value trace_flags )] => (
    is          => 'rw',
    isa         => 'Int',
);

has bt_slots => (
    is          => 'rw'
);

has [qw( node_pkg rule_vars )] => (
    is          => 'rw',
);

has registers => (
    is          => 'ro',
    isa         => 'ArrayRef',
);

sub iter_slots { $_[0]->{bt_slots} }

no Moose;
__PACKAGE__->meta->make_immutable;

sub current_rule_name {
    my ($self) = @_;
    return defined ($self->{rule_index}) ? 
        ($self->LITERAL_LIST->[$self->{rule_index}] || '??') :
        '<unknown>';
}

our @_STACK_STATE = qw(
    rule_index
    ok_return
    fail_return
    set_match_value
    trace_flags
    bt_slots
    node_pkg
    rule_vars
    registers
);

sub register {
    my ($self, $reg_no) = @_;
    return $self->{registers}->[$reg_no] if 2 == @_;
    return ($self->{registers} ||= [])->[$reg_no] = $_[2];
}

sub rule_def_names_on_stack {
    my ($self) = @_;
    return map {
        $self->LITERAL_LIST->[$_->[0]] || '<RuleDef: ' . $_ . '>'
    } @{$self->ctx_stack};
}

sub push_and_init {
    my ($self) = @_;
    push @{$self->{ctx_stack}}, [ @$self{@_STACK_STATE} ];
    $self->{bt_slots}   = undef;
    $self->{node_pkg}   = undef;
    $self->{rule_vars}  = undef;
    $self->{registers}  = undef;
    # rule_index, ok_return, fail_return amd set_match_value
    # are set the rule caller
}

sub pop_saved {
    my ($self) = @_;
    @$self{@_STACK_STATE} = @{pop @{$self->{ctx_stack}}};
}

use Scalar::Util qw( refaddr reftype );
use overload '""'       => 'to_string',
             'bool'     => '_bool',
            '=='        => '_eqeq',
            fallback    => 1;

sub _perl_scalar($$) {
    my ($value, $max_len) = @_;
    $max_len = 20 if $max_len < 20;
    return 'undef' unless defined $value;
    return $value =~ m/[-+]?[0-9]+(?:)?/ ? $value :
            "'" . substr ($value, 0, $max_len) .
                (length ($value) > $max_len ? '...' : '') . "'";
}

sub _perl_value_str($$);
sub _perl_value_str($$) {
    my ($value, $max_len) = @_;
    return 'undef' unless defined $value;
    return _perl_scalar ($value, $max_len) unless ref $value;

    my $text = '';
    for (reftype ($value)) {
        when ('ARRAY') {
            return '[]' unless @$value;
            return '[ ... ]' unless $max_len > 7;
            my $i = 0;
            my $text = '[ ';
            for (@$value) {
                $i++;
                $text .= _perl_value_str ($_, $max_len - length ($text)) . ', ';
                if (length ($text) >= $max_len) {
                    $text .= '...' if $i < @$value;
                    last;
                }
            }
            return $text . ' ]';
        }
        when ('HASH') {
            return '{}' unless scalar (keys (%$value));
            return '{ ... }' unless $max_len > 7;
            my $i = 0;
            my $text = '{ ';
            for (sort keys (%$value)) {
                $text .= "$_ => " . _perl_value_str ($value->{$_}, $max_len - length ($text) - length ($_)) . ', ';
                if (length ($text) >= $max_len) {
                    $text .= '...' if $i < @$value;
                    last;
                }
            }
            return $text . ' }';
        }
    }
}

sub _rule_ident($$$$) {
    my ($self, $rule_index, $ok_return, $fail_return) = @_;
    return sprintf ('%-25s',
        defined ($rule_index) ?
                ($self->LITERAL_LIST->[$rule_index] || $rule_index) : ''
    ) .
    sprintf (' ok: %-5s fail: %-5s', 
        (defined ($ok_return) ? sprintf ('%05d', $ok_return) : 'undef'), 
        (defined ($fail_return) ? sprintf ('%05d', $fail_return) : 'undef'), 
    );
}

sub to_string {
    my ($self) = @_;
    my $text = ($self->match_status ? 'OK   ' : 'FAIL ') . 
               _rule_ident ($self, $self->rule_index, $self->ok_return, $self->fail_return) .
               "\nlast_match: << " . _perl_value_str ($self->last_match, 100) . ' >>';

    if (defined (my $stack = $self->ctx_stack)) {
        my $n = scalar @$stack;
        while (--$n >= 0) {
            my $values = $stack->[$n];
            $text .= "\n     " . _rule_ident ($self, $values->[0], $values->[1], $values->[2]);
        }
    }
    return $text;
}

sub _bool {
    no overloading;
    return defined ($_[0]);
}

sub _eqeq {
    no overloading;
    return $_[0] == $_[0];
}

1;

