####################################################################################################
# WW::Parse::PDA::ParserBase
####################################################################################################
package WW::Parse::PDA::ParserBase;
use feature qw(:5.12);
use strict;

=pod

=head1 NAME

WW::Parse::PDA::ParserBase - Convenience base class for parser front-ends

=head1 SYNOPSIS

    package The::Parser;
    use feature qw(:5.12);
    use strict;

    use Moose;
    extends 'WW::Parse::PDA::ParserBase';

    sub _parse_ops_pkg { 'The::Parser::ParserPDAOps' }

    sub parse_a_string {
        my ($self, $ident, $text, $trace_flags, $global_data) = @_;
        return $self->_parse_text ($ident, 'start_rule_name', \$text, $trace_flags, $global_data);
    }

    package main;

    use The::Parser;

    my $parser = The::Parser->new;
    my ($parse_result, $error_message) = $parser->parse_a_string ('ident_or_path', $the_text);
    die $error_message if $error_message;

=head1 DESCRIPTION

This class is a base class for building parsers that use C<< WW::Parse::PDA::Engine >>.
The engine class uses a set of descriptive tables to parse a text string in one method call.
See L<parser-gen-pda.pl> and L<WW::ParserGen::PDA> from the WW-ParserGen-PDA package
for how to generate a Perl package containing the required tables.

The parse engine does recursive-descent processing of parse rules from a given
starting rule. The parsing rules build an abstract syntax tree by returning class 
object instances or hash refs as their match value.

The parsing engine does not create a deep call stack even when parsing very deeply nested
rules. The recursion is handled in the parsing context object, not the call stack.

=head1 METHODS

=head2 _parse_ops_pkg ($self)

This method returns the fully qualified name of the package that defines the
parsing tables used by C<< WW::Parse::PDA::Engine >>. It must be implemented by
the subclass. This package is expected to to have certain class methods. The 
easiest way to generate a parse ops package is to use C<< parser-gen-pda.pl >> from
the C<< WW::ParserGen-PDA >> package.

=head2 _parse_text ($self, $ident, $rule, $text_ref, $trace_flags, $global_data)

This method returns the list C<< ($parse_result, $error_message) >>.

=over 4

=item $ident - string

This is an identifying string for the source of the text being parsed, it is used in error messages.

=item $rule - string

This is a string with the name of the starting parse rule. The result value of
this rule is is returned in C<< $parse_result >>.

=item $text_ref - ref to a string value

This reference has the text to be parsed. It will not be modified.

=item $trace_flags - optional int or undef

This value controls what kind of parsing output will be produced. When equal to 1, 
trace output will be sent to C<< *STDERR >> as C<< $text_ref >> is parsed. Setting this
value to 1 uses the default tracing package on the created parse engine. To have more control
over the trace output, call C<< use_trace_package >> before calling C<< _parse_text >>.

=item $global_data - optional perl value/object

This value is made available to grammar-defined parse ops via C<< $ctx->global_data >>.
Grammar-defined parse ops may use this value. The standard parse ops do not.

=back

=head2 _parse_test ($self, $start_rule, $text_ref, $trace_flags, $global_data)

This method returns the list C<< ($status, $parse_result_or_error_message) >>. 
See L<WW::Parse::PDA::Engine::parse_text> for the definition of the returned list. The
method arguments are the same as _parse_text except that C<< $ident >> is omitted.
Unit tests of the parser may find this method useful.

=head2 use_trace_package ($self, $trace_pkg_name, $trace_output_handle)

This method configures the parse engine instance to enable parse tracing.
Trace output is normally disabled as it substantially slows the parser down even
when not producing trace output. See L<WW::Parse::PDA::Engine> for a full
description of the arguments.

=over 4

=item $trace_pkg_name - optional string

The fully qualified name of the package to use for generating trace output. The default is
WW::Parse::PDA::Trace.

=item $trace_output_handle - optional output handle

Trace output is written to this handle. The default is C<< \*STDERR >>.

=back

=head1 BUGS

The parse engine has only been tested with Perl 5.12 so it has been
flagged to require 5.12 features. Earlier Perls might work, but
they must be able to use Moose.

None known at the moment.

=head1 SEE ALSO

parser-gen-pda.pl and WW::ParserGen::PDA from WW-ParserGen-PDA

=head1 COPYRIGHT

Copyright (c) 2013 by Lee Woodworth.  All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

use WW::Parse::PDA::Engine;

use Moose;

has _pda_engine => (
    is          => 'ro',
    isa         => 'WW::Parse::PDA::Engine',
    init_arg    => undef,
);

sub _parse_ops_pkg { die "subclass must implement" }

our %_PDA_ENGINES;
sub BUILD {
    my ($self, $args) = @_;
    my $op_pkg = $self->_parse_ops_pkg;
    my $engine = $_PDA_ENGINES{$op_pkg};
    unless ($engine) {
        eval ("require $op_pkg");
        if ($@) {
            my $msg = $@;
            die (ref ($self) . ": error in require $op_pkg:\n$msg\n");
        }

        $engine = $_PDA_ENGINES{$op_pkg} =
            WW::Parse::PDA::Engine->new ( %{ $op_pkg->get_op_tables } );
    }
    $engine->use_trace_package (
        $args->{trace_handler} ? ( $args->{trace_handler} ) : ( )
    ) if $args->{trace_flags};
    $self->{_pda_engine} = $engine;
}

# returns ( $match_result, $error_message )
sub _parse_text {
    my ($self, $ident, $rule, $text_ref, $trace_flags, $global_data) = @_;
    $self->_pda_engine->use_trace_package if $trace_flags;
    my ($status, $match) = $self->_pda_engine->parse_text ($rule, $text_ref, $trace_flags, $global_data);
    return $status ? ( $match ) : ( undef, ($match || 'parser error'));
}

# returns ( $status, $value_or_error )
sub _parse_test {
    my ($self, $start_rule, $text_ref, $trace_flags, $global_data) = @_;
    my $pda_engine = $self->_pda_engine;
    if ($trace_flags) {
        $pda_engine->use_trace_package unless $pda_engine->trace_handler;
    }
    else {
        $pda_engine->set_trace_handler (undef);
    }
    return $pda_engine->parse_text ($start_rule, $text_ref, $trace_flags, $global_data);
}

sub use_trace_package {
    my ($self, $trace_pkg, $trace_handle) = @_;
    $self->_pda_engine->use_trace_package ($trace_pkg, $trace_handle);
}

no Moose;
__PACKAGE__->meta->make_immutable;

sub get_op_tables {
    my ($self) = @_;
    my $op_pkg = $self->_parser_ops_pkg;
    return $op_pkg->get_op_tables;
}

1;

