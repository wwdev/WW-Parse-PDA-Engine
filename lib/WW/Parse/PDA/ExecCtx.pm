package WW::Parse::PDA::ExecCtx;
use feature qw(:5.12);
use strict;

=pod

=head1 NAME

WW::Parse::PDA::ExecCtx - Parsing Context for the Parse Engine

=head1 DESCRIPTION

An an instance of this class represents the state of the parser PDA. 
It maintains the data used for backtracking, rule variables, and for
generating trace output.

The attribute values are in two categories: the stacked set and the global set.
Values in the global set are shared beteween all parsing operations and
thus all rules. The stacked set's values are saved when a sub-rule is called,
and then restored when the sub-rule returns. These values are isolated between
different rule calls.

=head1 GLOBAL VALUES

=head2 text_ref - read-only ref to string value

This is the text string being parsed. Parsing ops must not modify the value.
The standard perl function, C<< pos() >>, returns the current parsing position within
the string. Parsing ops may modify the position to consume text, for example:

    my $text_ref = $ctx->text_ref;
    my $start_pos = pos ($$text_ref);
    ... some matching code, could be a regex starting with \G, ...
    pos($$text_ref) = $start_pos + $match_length;
    $ctx->{match_status} = 1

=head2 gloabl_data - arbitrary perl value

This value is copied from the C<< $global_data >> parameter of the parser
engine's C<< parse_text method >>. Grammer-defined parsing ops may use this value
for maintaining their own additional state. Beware though, no parsing op is called 
to indicate when backtracking occurs.

=head2 match_status - boolean value

This value indicates whether a parsing op succeeded: it either matched and consumed
some text, or matched a predicate (e.g. an integer value being in a particular range).
Parsing ops set this value as follows:

    $ctx->{match_status} = 1;       # success
    $ctx->{match_status} = undef;   # fail

=head2 match_value - arbitray perl value

This value holds the result from the execution of a parsing op, for example the
text matched by regex. The value does not have to be a scalar. The value is volatile
as it may change and should not be relied on for saving a matched value. See the 
registers description in L</STACKED VALUES> for that. A parsing op sets the value as follows:

    $ctx->{match_value} = Some::Pkg->new ( ... );
    # or any other value needed for the AST

=head2 trace_handler - instace of a trace handler

This read-only value contains an object that produces trace output. It may be undef.
Only the parse engine uses this value.

=head1 STACKED VALUES

While parsing a rule, each rule has its own isolated copies of these
attributes. This also applies to recursive rule calls.

=head2 rule_index - read-only integer

This value contains the entry point index for the current rule.
Used when generating error messages or trace output.

=head2 ok_return, fail_return - read-only integer

These values hold the op indices to return to on a rule's
success or fail return.

=head2 set_match_value - read-only boolean

This value is used by some ops to control what value is stored
in C<< $ctx->{match_value} >>. Not of interest to grammar-defined parsing ops.

=head2 trace_flags - read-only integer

This value has the currently effective trace flags. The C<< &&trace_flags >>
directive can set this value for a rule. Note that since this is a stacked
value, one can use:

    &&trace_flags[0] 

in the top-level rule to disable trace output. An then use:

    &&trace_flags[1]

in a particular rule to trace just that rule's parsing ops.

=head2 node_pkg - read-only string or undef

If the rule definition defined a node package, this value
will have the expanded name (i.e. the grammar's 
C<< @node_package_prefix >> applied if necessary). On a successful
rule return, the match value will be set as follows:

    $ctx->{match_value} = $ctx->node_pkg->new (
        %{ $ctx->rule_vars }
    );

=head2 rule_vars - read-write hash ref or undef

If the rule definition defined a node package or just rule var/value names,
this value be a hash ref. Otherwise it will be undef. When the hash is defined,
it starts as an empty hash. Each rule call has its own distinct hash. Parsing ops
may assign arbitrary values to the hash. On successful rule return, the last
match value will be set as follows:

    $ctx->{match_value} = $ctx->rule_vars;

=head2 registers - regsiter set

Each rule call has a set of 10 registers, numbered 0-9. The regsiter values
are isolated between rule calls, but not between parsing ops in the same rule.
Parsing ops can place arbitrary values in a register or assign the C<< match_value >>
value from a register. Registers are useful for saving intermediate parse results
from multiple rule calls.

To read a register value:

    my $r0 = $ctx->register (0); # read register 0

To set a register:

    $ctx->register (0, $value);  # set register 0

The set method-call returns the C<< $value >> argument.

=head1 SEE ALSO

WW::Parse::PDA::Engine, WW::Parse::PDA::ParserBase, and
WW::ParserGen::PDA::Intro from the WW-ParserGen-PDA package.

=head1 COPYRIGHT

Copyright (c) 2013 by Lee Woodworth. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

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

has match_value => (
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

#has [qw( temp1 temp2 )] => (
#    is          => 'ro',
#    init_arg    => undef,
#);

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

has value_slots => (
    is          => 'rw'
);

has [qw( node_pkg rule_vars )] => (
    is          => 'rw',
);

has registers => (
    is          => 'ro',
    isa         => 'ArrayRef',
);

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
    value_slots
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
    $self->{value_slots} = undef;
    $self->{node_pkg}    = undef;
    $self->{rule_vars}   = undef;
    $self->{registers}   = undef;
    # rule_index, ok_return, fail_return amd set_match_value
    # are set by the rule caller
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
               "\nmatch_value: << " . _perl_value_str ($self->match_value, 100) . ' >>';

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

