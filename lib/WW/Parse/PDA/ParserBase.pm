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

This class is a convience class for building parsers that use WW::Parse::PDA::Engine.
The engine class uses a set of descriptive tables to parse a text string in one call.
See L<parser-gen-pda.pl> and L<WW::ParserGen::PDA> from the WW-ParserGen-PDA package
for how to generate a Perl package containing the required tables.

The parse engine does recursive-descent processing of parse rules from a given
starting rule. The parsing rules build an abstract syntax tree by returning class 
object instances or hash refs as their match value.

=head1 METHODS

=over 4

=item _parse_ops_pkg ($self)

This method returns the fully qualified name of the package that defines the
parsing tables used by WW::Parse::PDA::Engine. It must be implemented by
the subclass.

=item _parse_text ($self, $ident, $rule, $text_ref, $trace_flags, $global_data)

This method returns the list ($parse_result, $error_message). $ident is a string
identifying the source of the text being parsed, it is used in error messages.
$rule is a string with the name of the starting parse rule. The result value of
this rule is is returned in $parse_result. $text_ref is reference to a string
containing the text to be parsed. $trace_flags is an optional integer controlling
tracing output. When true, trace output will be sent to STDERR as $text_ref is
parsed. $global_data is optional perl value/object that will be made avaliable
to parsing rules.

=item _parse_test ($self, $start_rule, $text_ref, $trace_flags, $global_data)

This method returns the list ($status, $parse_result_or_error_message). The
arguments are the same as _parse_text except that $ident is omitted. The
intended use of this method for unit tests of the parser.

=item use_trace_package ($self, $trace_pkg_name, $trace_output_handle)

This method configures the parse engine instance to enable parse tracing.
Trace is normally disabled as it substantially slows the parser down even
when not producing trace output.

$trace_pkg_name is an optional string containing the fully-qualified name
of the package to use for generating trace output. The default is
WW::Parse::PDA::Trace. $trace_output_handle is an IO::Handle compatible
object (supports print and say) where trace output is written. The default
is \*STDERR.

=back

=head1 BUGS

The parse engine has only been tested with Perl 5.12 so it has been
flagged to require 5.12 features. Earlier Perls mitgh work, but
they must be able to use Moose.

None known at the moment.

=head1 SEE ALSO

parser-gen-pda.pl, WW::ParserGen::PDA from WW-ParserGen-PDA

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

