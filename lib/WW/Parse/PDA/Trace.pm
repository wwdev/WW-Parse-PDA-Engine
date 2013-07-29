package WW::Parse::PDA::Trace;
use feature qw(:5.12);
use strict;

=pod

=head1 NAME

WW::Parse::PDA::Trace - Parsing Op Tracer

=head1 DESCRIPTION

This class generates tracing output from a parsing context.

=head1 COPYRIGHT

Copyright (c) 2013 by Lee Woodworth. All rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

use Scalar::Util qw( refaddr reftype );
use WW::Parse::PDA::TraceConsts qw( :all );

use Moose;

has [qw( OP_ADDRESS_NAMES    LITERAL_LIST       REGEX_LIST
         RULE_DEF_INDEXES    RULE_DEF_NAMES     OP_LIST
         OP_DEFS             OP_ADDRESS_TRACE_FLAGS
)] => (
    is          => 'ro',
    required    => 1,
);

has [qw( ofh _op_defs_map )] => (
    is          => 'ro',
);

sub BUILD {
    my ($self, $args) = @_;
    $self->{ofh} ||= \*STDERR;
    $self->{_op_defs_map} = { map { ( $_->op_type, $_ ) } @{$self->OP_DEFS} };
}

no Moose;
__PACKAGE__->meta->make_immutable;

sub _max_field($$);
sub _fixed_field($$);
sub _rfixed_field($$);
sub _multiline($$$);
sub _perl_scalar($$);
sub _perl_value_str($$);

sub trace {
    my ($self, $ctx, $op_index, $op_list, $trace_flags) = @_;
    my $ofh = $self->ofh;
    my $op_addr = refaddr ($op_list->[$op_index]);
    my $op_trace_flags = $self->OP_ADDRESS_TRACE_FLAGS->{$op_addr} || 0;
    return unless ($op_trace_flags & $trace_flags) != 0;

    my $op_type = $self->OP_ADDRESS_NAMES->{$op_addr} ||
            "<OP: " . $op_list->[$op_index] . ">";
    print $ofh "===== op_index: ", sprintf ('%05d/%-20s', $op_index, $op_type), ('=' x 80), "\n",
        '   Rule:       ', sprintf (
                '%-35s', (defined ($ctx->rule_index) ? $ctx->current_rule_name : '<Rule: ' . $ctx->rule_index . '>')
            ),
        ($ctx->node_pkg ? ' Package: ' . $ctx->node_pkg : '');
    if (my @stack_rules = $ctx->rule_def_names_on_stack) {
        print $ofh ' <<';
        while (my $name = pop @stack_rules) {
            print $ofh ' ', $name;
        }
        print $ofh ' >>';
    }
    say $ofh '';

    my $text_ref = $ctx->text_ref;
    my $offset = pos ($$text_ref);
    my $text = substr ($$text_ref, $offset, 90);
    $text =~ s/[\x00-\x09\x0B-\x1F\x80-\xFF]/./g;
    $text =~ s/\n/\\n/g;
    say $ofh "   Offset:     ", (defined ($offset) ? sprintf ('%05d', $offset) :' undef'),
        ' [', _fixed_field (90, $text), ']';

    $self->_trace_match_status ($ctx);
    $self->_trace_rule_vars ($ctx);
    $self->_trace_registers ($ctx);
    $self->_trace_op_args ($op_type, $op_index, $op_list);
    say $ofh '';
    $self->debug_break ($ctx, $op_index, $op_list);
}

sub _trace_rule_vars {
    my ($self, $ctx) = @_;
    my $ofh = $self->ofh;
    my $rule_vars = $ctx->rule_vars;
    return unless $rule_vars && scalar (keys (%$rule_vars));

    my $i = 0;
    for my $k (sort (keys (%$rule_vars))) {
        next unless defined $rule_vars->{$k};
        my $indent = '               ';
        unless ($i++) {
            say $ofh '               ', ('-' x 100);
            $indent = "   Rule Vars:  ";
        }
        say $ofh $indent, _fixed_field (20, $k), ' => ', 
            _max_field (90, _perl_value_str ($rule_vars->{$k}, 90));
    }
}

sub _trace_registers {
    my ($self, $ctx) = @_;
    my $ofh = $self->ofh;
    my $registers = $ctx->registers;
    return unless $registers && @$registers;

    say $ofh '              ', ('-' x 100);
    my $rule_vars = $ctx->rule_vars;
    for (my $i=0; $i<@$registers; $i += 2) {
        my $indent = '   ' . ($i ? '         ' : 'Registers:') . '  ';
        print $ofh $indent, "r$i: ", _fixed_field (40, _perl_value_str ($registers->[$i], 40));
        if ((my $j = $i + 1) < @$registers) {
            print $ofh '                ', "r$j: ", _fixed_field (40, _perl_value_str ($registers->[$j], 40));
        }
        say $ofh '';
    }
}

sub _trace_op_args {
    my ($self, $op_type, $op_index, $op_list) = @_;
    my $op_def = $self->_op_defs_map->{
        ($op_type =~ m/^regex[\d]+$/) ? 'regex' : $op_type
    };
    my $arg_names = $op_def ? $op_def->arg_names : undef;
    my $arg_types = $op_def ? $op_def->arg_types : undef;

    my $ofh = $self->ofh;
    if ($arg_types) {
        say $ofh '               ', ('-' x 100);
        my $j = 0;
        for my $arg_type (@$arg_types) {
            if (($j++ % 3) == 0) {
                my $indent = $j < 2 ? '   Op Args:    ' : (' ' x 16);
                print $ofh $indent;
            }

            my $op_arg  = $op_list->[$op_index + $j];
            for ($arg_type) {
                when (!defined ($op_arg)) { $op_arg = '<undef>'; }
                when ('Int')              { $op_arg = $op_arg; }
                when ('OpIndex')          { }
                when ('Str') {
                    $op_arg = $self->LITERAL_LIST->[$op_arg] ?
                        '[' . _max_field (25, $self->LITERAL_LIST->[$op_arg]) . ']' :
                        '<Str: ' . _max_field (21, $op_arg) . '>';
                }
                when ('Regex') {
                    $op_arg = $self->LITERAL_LIST->[$op_arg] ?
                        '[' . _max_field (25, $self->LITERAL_LIST->[$op_arg]) . ']' :
                        '<Regex: ' . _max_field (19, $op_arg) . '>';
                }
                when ('RuleIndex') {
                    $op_arg = $self->RULE_DEF_NAMES->{$op_arg} ||
                            '<RuleIndex: ' . $op_arg . '>';
                }
                default {
                    $op_arg = '[' . _max_field (40, _perl_value_str ($op_arg, 40)) . ']';
                }
            }
            print $ofh _fixed_field (12, $arg_names->[$j - 1] . ':'), ' ', _fixed_field (30, $op_arg), ' ';
            if (($j % 3) == 0) { say $ofh ''; }
        }
        if (($j % 3) != 0) { say $ofh ''; }
    }
}

sub _trace_match_status {
    my ($self, $ctx) = @_;
    my $ofh = $self->ofh;
    my $line = '   Prev Match: ***** ' . ($ctx->match_status ? 'OK  ' : 'FAIL') . ' *****';
    my $value = $ctx->match_value;
    $line .= ref ($value) || length ($value) > 20 ? 
        ' ' . _perl_value_str ($value, 80) . 
            ($ctx->value_slots ? "\n" . (' ' x 14) : '') :
        ' ' . _perl_value_str ($value, 20) . ' ';

    if (my $slots = $ctx->value_slots) {
        $line .= ' VALUE [';
        my $i = 0;
        for (@$slots) {
            $line .= ' ' if $i++;
            $line .= defined ($_) ? sprintf ('%05d', $_) : 'undef';
        }
        $line .= ']';
    }
    say $ofh $line;
}

sub debug_break {
    my ($self, $ctx, $op_index, $op_list) = @_;
    if ($ctx->trace_flags && $ctx->trace_flags > 15) {
        say { $self->ofh } '***** debug_break *****';
    }
}

sub _perl_scalar($$) {
    my ($value, $max_len) = @_;
    $max_len = 20 if $max_len < 20;
    return 'undef' unless defined $value; 
    return $value =~ m/[-+]?[0-9]+(?:)?/ ? $value :
            "'" . substr ($value, 0, $max_len) .
                (length ($value) > $max_len ? '...' : '') . "'";
}

sub _max_field($$) {
    my ($width, $text) = @_;
    $text = '<undef>' unless defined $text;
    my $l = length ($text);
    return $l <= $width ? $text : substr ($text, 0, $width);
}

sub _fixed_field($$) {
    my ($width, $text) = @_;
    $text = '<undef>' unless defined $text;
    my $l = length ($text);
    return $l == $width ? $text :
           $l < $width  ? $text . (' ' x ($width - $l)) :
                          substr ($text, 0, $width);
}
    
sub _rfixed_field($$) {
    my ($width, $text) = @_;
    $text = '<undef>' unless defined $text;
    my $l = length ($text);
    return $l == $width ? $text :
           $l < $width  ? (' ' x ($width - $l)) . $text :
                          substr ($text, 0, $width);
}

sub _mutiline($$$) {
    my ($num_lines, $line_len, $text) = @_;
    my @lines;
    my $i = 0;
    while ($i < length ($text) && $num_lines) {
        push @lines, substr ($text, $i, $line_len);
        $i += $line_len;
        $num_lines--;
    }
    return @lines;
}

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
            my $i = 0; my $n = scalar (keys (%$value));
            my $text = '{ ';
            for (sort keys (%$value)) {
                $text .= "$_ => " . _perl_value_str ($value->{$_}, $max_len - length ($text) - length ($_)) . ', ';
                if (length ($text) >= $max_len) {
                    $text .= '...' if $i < $n;
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

1;

