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
Parsing rules defined by the tables are executed until they match
or signal failure.

See L<parser-gen-pda.pl> and L<WW::ParserGen::PDA> from the WW-ParserGen-PDA package
for how to generate a Perl package containing the required tables.

=head1 SEE ALSO

WW::Parse::PDA::ParserBase, and
parser-gen-pda.pl, WW::ParserGen::PDA from WW-ParserGen-PDA

=head1 COPYRIGHT

Copyright (c) 2013 by Lee Woodworth.  All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

use Scalar::Util qw( blessed refaddr );
use WW::Parse::PDA::ExecCtx;
use WW::Parse::PDA::TraceConsts qw( :all );

our $VERSION = '0.012000';

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
        ( 1, $ctx->last_match ) :
        ( undef, $ctx->error_message );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

