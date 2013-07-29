##########################################################################################
# WW::Parse::PDA::Engine
##########################################################################################
package WW::Parse::PDA::Engine;
use feature qw(:5.12);
use strict;

=pod

=head1 NAME

WW::Parse::PDA::Engine - Push Down Automaton (PDA) Parse Engine

=head1 DESCRIPTION

This class implements a parsing engine that is driven by data tables.
Parsing rules defined by the tables are executed in recursive-descent order.
I.e., a top-level rule is called and it in turn calls sub-rules.

See L<parser-gen-pda.pl> and L<WW::ParserGen::PDA> from the WW-ParserGen-PDA package
for how to generate a Perl package containing the required tables. See L<WW::Parse::PDA::ExecCtx>
for the parsing state available to grammar-defined parsing ops.

=head1 ATTRIBUTES

=head2 trace_flags - int or undef

The control flags for tracing output. The most useful values are:

    1           - trace interesting events, e.g. literal match, rule call, ...
    undef or 0  - no tracing

Use C<< $engine->set_trace_flags ($flags) >> to set the value post construction.
Note that just setting the flags won't generate trace output. The trace handler
must be set via C<< set_trace_handler >> or C<< use_trace_package >>.

=head1 METHODS

=head2 new ($pkg, trace_flags => $trace_flags, ... implementation dependent args ...)

Create a new parsing engine. It is recommended to use a subclass of C<<WW::Parse::PDA::ParserBase>>
rather than creating a parse engine directly. The exact nature of the parsing tables is implementation
private and subject to change.

=head2 use_trace_package ($self, $trace_pkg, $trace_handle)

This is the easy way to enable tracing.

=over 4

=item $trace_pkg - optional fully qualified package name

The package will be required and an instance created via new. See L<WW::Parse::PDA::Trace>
for the interface the package must support. The default value for C<< $trace_package >> is
'WW::Parse::PDA::Trace'.

=item $trace_handle - optional output handle

Trace output is written to this handle. The handle must be usable with print/say. Defaults
to C<< \*STDERR >>.

=back

=head2 parse_text ($self, $rule_name, $text_ref, $trace_flags, $global_data)

This method parses the given text and returns the list C<< ($status, $parse_result_or_error_message) >>.
C<< $status >> is true for a successful parse. On success, C<< $parse_result_or_error_message >> 
has the value returned by the start rule.  Otherwise, the value is the parsing error message.

Note that a rule can return an undef value!

=over

=item $rule_name - string

This is the name of the staring rule. The result of the rule is returned as C<< $parse_result_or_error_message >>.

=item $text_ref - ref to a string

This is the text to parse. It will not be modified (as long as grammar-defined parsing ops obey the rules).

=item $trace_flags optional int

This sets the initial tracing flags value. See the C<< trace_flags >> attribute for details.

=item $global_data - optional perl value

This value is set as the parsing context's C<< global_data >> attribute. Grammer-defined
parsing ops may use this value, The standard parsing ops do not.

=back

=head2 set_trace_handler ($self, $handler)

Set the trace handling object. The object must implement a C<< trace >> method that takes
the same parameters as C<< WW::Parse::PDA::Trace::trace >>.

=head1 SEE ALSO

WW::Parse::PDA::ParserBase, and
parser-gen-pda.pl, WW::ParserGen::PDA from WW-ParserGen-PDA

=head1 COPYRIGHT

Copyright (c) 2013 by Lee Woodworth. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

use Scalar::Util qw( blessed refaddr );
use WW::Parse::PDA::ExecCtx;
use WW::Parse::PDA::TraceConsts qw( :all );

our $VERSION = '0.012001';

use Moose;

has [qw( OP_ADDRESS_NAMES    LITERAL_LIST       REGEX_LIST
         RULE_DEF_INDEXES    RULE_DEF_NAMES     OP_LIST
         OP_DEFS             OP_ADDRESS_TRACE_FLAGS
)] => (
    is          => 'ro',
    required    => 1,
);

has trace_handler => (
    is          => 'ro',
    isa         => 'Object',
);

sub set_trace_handler {
    my ($self, $handler) = @_;
    $self->_check_trace_handler ($handler);
    return $self->{trace_handler} = $handler;
}

has trace_flags => (
    is          => 'ro',
    isa         => 'Int',
    writer      => 'set_trace_flags',
);

sub BUILD {
    my ($self, $args) = @_;
    for (qw( OP_ADDRESS_NAMES OP_ADDRESS_TRACE_FLAGS RULE_DEF_INDEXES RULE_DEF_NAMES )) {
        my $v = $self->{$_};
        die ("$_ is not a hash ref") unless ref ($v) eq 'HASH';
        die ("$_ is empty") unless scalar (keys (%$v));
    }

    for (qw( LITERAL_LIST REGEX_LIST OP_LIST OP_DEFS )) {
        my $v = $self->{$_};
        die ("$_ is not an array ref") unless ref ($v) eq 'ARRAY';
    }

    for (qw( OP_LIST OP_DEFS )) {
        my $v = $self->{$_};
        die ("$_ is empty") unless @$v;
    }

    $self->_check_trace_handler ($self->trace_handler);
}

sub _check_trace_handler {
    my ($self, $trace_handler) = @_;
    return unless defined $trace_handler;
    die ("$trace_handler is not a blessed object with a trace method")
        unless blessed ($trace_handler) && $trace_handler->can ('trace');
}

sub use_trace_package {
    my ($self, $trace_pkg, $trace_handle) = @_;
    $trace_pkg ||= 'WW::Parse::PDA::Trace';
    eval ("require $trace_pkg;");
    if (my $msg = $@) {
        die "error loading trace package $trace_pkg:\n$msg";
    }
    $self->set_trace_handler (
        $trace_pkg->new (
            ofh => $trace_handle,
            map { ( $_, $self->{$_} ) } qw( 
                OP_ADDRESS_NAMES    LITERAL_LIST       REGEX_LIST
                RULE_DEF_INDEXES    RULE_DEF_NAMES     OP_LIST
                OP_DEFS             OP_ADDRESS_TRACE_FLAGS
            ),
        ),
    );
}

sub parse_text {
    my ($self, $rule_name, $text_ref, $trace_flags, $global_data) = @_;
    die ("text_ref is undef") unless defined $text_ref;

    my $rule_index = $self->RULE_DEF_INDEXES->{$rule_name};
    die ("no rule named '$rule_name'") unless defined $rule_index;

    my $ctx = WW::Parse::PDA::ExecCtx->new (
        text_ref        => $text_ref,
        trace_handler   => $self->trace_handler,
        ($global_data ? ( global_data => $global_data ) : ( )),
        map { ( $_, $self->{$_} ) } qw(
            OP_ADDRESS_NAMES    LITERAL_LIST    REGEX_LIST
            RULE_DEF_INDEXES    RULE_DEF_NAMES
        )
    );

    my $op_list = $self->OP_LIST;
    $ctx->ok_return       (-1);
    $ctx->fail_return     (-2);
    $ctx->set_match_value (1);
    $ctx->trace_flags     (trace_flags_from_str ($trace_flags ||= 0));

    pos ($$text_ref) = 0;
    my $op_index = $rule_index;

    if (my $trace_handler = $self->trace_handler) {
        $ctx->rule_index ($op_index);
        while ($op_index >= 0) {
            my $op = $op_list->[$op_index];
            $trace_handler->trace ($ctx, $op_index, $op_list, $trace_flags)
                if $ctx->trace_flags;
            unless (ref ($op) eq "CODE") {
                say STDERR "***** op_list error at index $op_index: $op is not a code ref";
                WW::Parse::PDA::OpDefs::debug_break (
                    $ctx, $op_index, $op_list, pos (${$ctx->text_ref}), $ctx->text_ref
                );
            }
            $op_index = $op->($ctx, $op_index, $op_list);
        }
    }
    else {
        while ($op_index >= 0) {
            my $op = $op_list->[$op_index];
            $op_index = $op->($ctx, $op_index, $op_list);
        }
    }
    $self->{trace_flags} = $ctx->trace_flags;

    return $op_index == -1 ?
        ( 1, $ctx->match_value ) :
        ( undef, $ctx->error_message );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

