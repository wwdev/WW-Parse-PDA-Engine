package WW::Parse::PDA::OpDefs;
use feature qw(:5.12);
use strict;

use Scalar::Util qw( reftype );

use WW::Parse::PDA::OpDef;
use WW::Parse::PDA::VarSetOps qw( :all );
use WW::Parse::PDA::TraceConsts qw( :all );

our $VERSION = '0.012000';
our $MIN_COMPAT_VERSION = '0.012000';
sub PDA_ENGINE_VERSION() { '0.012000' };

#-------------------------------------------------------------------------------

sub _parse_position_ident($) {
    my ($ctx) = @_;

    my $text_ref = $ctx->text_ref;
    my $char_offset = pos ($$text_ref);
    $char_offset = length ($$text_ref) - 1 if $char_offset >= length ($$text_ref);

    my $line_no = 1;
    my $start_offset = 0;
    my $end_offset = 0;
    while ($start_offset <= $char_offset) {
        $end_offset = index ($$text_ref, "\x0A", $start_offset);
        $end_offset = length ($$text_ref) + 1 if $end_offset < $start_offset;
        last if $end_offset >= $char_offset;
        $line_no++;
        $start_offset = $end_offset + 1;
    }

    my $error_line = substr ($$text_ref, $start_offset, $end_offset - $start_offset);
    return " at line $line_no, char " . (pos ($$text_ref) - $start_offset + 1) .
            " while parsing " . $ctx->current_rule_name . "\n" . $error_line;
}

sub debug_break($$$$$) {
    my ($ctx, $op_index, $op_list, $offset, $text_ref) = @_;
    # next statment is so we can step over the arg vars assign without exiting
    print STDERR "=======================";
}

sub debug_break_op($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $text_ref = $ctx->text_ref;
    my $offset   = pos ($$text_ref);
    my $message = $ctx->LITERAL_LIST->[$op_list->[$op_index + 1]];
    say STDERR "debug break: ", $message, 
        "\n    at ", _parse_position_ident ($ctx);
    debug_break ($ctx, $op_index, $op_list, $offset, $text_ref);
    $ctx->{match_status} = 1;
    return $op_index + 2;
}

sub trace_flags($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{trace_flags} = $op_list->[$op_index + 1];
    return $op_index + 2;
}

sub fail($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{match_status} = undef;
    return $op_index + 1;
}

sub _var_get($$) {
    my ($ctx, $var_name) = @_;
    for ($var_name) {
        when ('*last_match*')       { return $ctx->{last_match}; }
        when ($_ =~ m/^[*]([\d])/)  {
            my $index = int ($1);
            return $ctx->{registers} ? $ctx->{registers}->[$index] : undef; 
        }
        when ('*offset*')           {
            my $text_ref = $ctx->{text_ref};
            return pos ($$text_ref);
        }
        when ('*rule_vars*')        {
            my $rule_vars = $ctx->{rule_vars};
            die ("no rule_vars defined, cannot get $var_name")
                unless $rule_vars;
            return $rule_vars;
        }
        default {
            my $rule_vars = $ctx->{rule_vars};
            die ("no rule_vars defined, cannot get $var_name")
                unless $rule_vars;
            return $rule_vars->{$var_name};
        }
    }
}

sub _var_set($$$$) {
    my ($ctx, $var_name_index, $set_op_code, $value) = @_;

    my $var_name = $ctx->{LITERAL_LIST}->[$var_name_index];
    my $dest_ref;
    if ($var_name eq '*last_match*') { 
        $dest_ref = \($ctx->{last_match}); 
    }
    elsif ($var_name =~ m/^[*]([\d])/) {
        my $index = int ($1);
        my $registers = $ctx->{registers};
        unless (defined ($registers)) {
            $registers = $ctx->{registers} = [];
            $registers->[$index] = undef;
        }
        $dest_ref = \($registers->[$index]);
    }
    elsif ($var_name eq '*offset*') {
        die ('parse offset can only be assigned to ' . _parse_position_ident ($ctx))
            unless $set_op_code == VAR_SET_OP_SET;
        pos (${$ctx->text_ref}) = $value;
        return;
    }
    elsif ($var_name eq '*rule_vars*') { 
        die ("no rule_vars defined, cannot get $var_name ". _parse_position_ident ($ctx))
            unless $ctx->{rule_vars};
        $dest_ref = \($ctx->{rule_vars}); 
    }
    else {
        my $rule_vars = $ctx->{rule_vars};
        die ("no rule_vars defined, cannot set $var_name " . _parse_position_ident ($ctx))
            unless $rule_vars;
        $dest_ref = \($rule_vars->{$var_name});
    }

    if ($set_op_code == VAR_SET_OP_SET) {
        $$dest_ref = $value;
    }
    elsif ($set_op_code == VAR_SET_OP_SETIF) {
        if (ref ($value) eq 'HASH' && ref ($$dest_ref)) {
            while (my ($k, $v) = each (%$value)) {
                $$dest_ref->{$k} = $v
                    unless defined $$dest_ref->{$k};
            }
        } else {
            $$dest_ref = $value unless defined $$dest_ref;
        }
    }
    elsif ($set_op_code == VAR_SET_OP_APPEND) {
        if (ref ($value) eq 'HASH' && ref ($$dest_ref)) {
            while (my ($k, $v) = each (%$value)) {
                if (defined ($$dest_ref->{$k})) {
                    $$dest_ref->{$k} .= $v if defined $v;
                    next;
                }
                $$dest_ref->{$k} = $v;
            }
        }
        elsif (defined ($$dest_ref)) {
            $$dest_ref .= $value if defined $value;
        }
        else {
            $$dest_ref = defined $value ? "$value" : undef;
        }
    }
    elsif ($set_op_code == VAR_SET_OP_A_APPEND) {
        $$dest_ref ||= [];
        die ("$var_name ($$dest_ref) is not an array " . _parse_position_ident ($ctx))
            unless reftype ($$dest_ref) eq 'ARRAY';
        push @{$$dest_ref}, $value;
    }
    elsif ($set_op_code == VAR_SET_OP_FA_APPEND) {
        $$dest_ref ||= [];
        die ("$var_name is not an array " . _parse_position_ident ($ctx))
            unless reftype ($$dest_ref) eq 'ARRAY';
        push @{$$dest_ref}, ref ($value) eq 'ARRAY' ? @$value : $value;
    }
    else {
        die "invalid var_set_op code: ", $set_op_code . _parse_position_ident ($ctx);
    }
}

sub dump_ctx($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->trace_handler->trace ($ctx, $op_index, $op_list, -1)
        if $ctx->trace_handler;
    return $op_index + 2;
}

sub _fatal_error_msg($$) {
    my ($ctx, $msg_params) = @_;
    unless ($msg_params && @$msg_params) {
        $ctx->{error_message} = "fatal error in " . $ctx->current_rule_name .
                                _parse_position_ident ($ctx);
        return -2;
    }

    my $msg = '';
    for (@$msg_params) {
        when ('$$') {
            $msg .= $ctx->last_match if defined $ctx->last_match;
        }
        when ($_ =~ /^[\$][\$]r(\d)$/) {
            my $reg = $ctx->register (int ($1));
            $msg .= $reg if defined $reg;
        }
        when ('$$offset') {
            $msg .= pos (${$ctx->text_ref});
        }
        when ('$$rule_vars') {
            my $hash = $ctx->rule_vars;
            $msg .= join (', ',
                map { $_ . ' => ' . $hash->{$_} } sort keys (%$hash)
            ) if $hash;
        }
        when ($_ =~ /^[\$]([_a-zA-Z][_a-zA-Z0-9]*)$/) {
            $msg .= $ctx->rule_vars->{$1} || $_
                if $ctx->rule_vars;
        }
        default {
            $msg .= $_;
        }
    }

    $ctx->{error_message} = $msg . _parse_position_ident ($ctx);
    return -2;
}

sub fatal($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    return _fatal_error_msg ($ctx, $op_list->[$op_index+1]);
}

sub rule_start($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $rule_index = $op_list->[$op_index + 1];
    $ctx->{rule_index}  = $op_list->[$op_index + 1];
    return $op_index + 3;
}

sub set_rule_vars($$$) {
    my ($ctx, $op_index, $op_list) = @_;
#    $ctx->{rule_vars} = { %{$op_list->[$op_index + 1]} };
    # Make a new hash every time
    $ctx->{rule_vars} = {};
    return $op_index + 2;
}

sub ok_return($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{match_status} = 1;
    $ctx->{last_match} = undef unless $ctx->{set_match_value};
    $op_index = $ctx->{ok_return};
    $ctx->pop_saved if $op_index >= 0;
    return $op_index;
}

sub hash_return($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{match_status} = 1;
    if ($ctx->{set_match_value}) {
        $ctx->{last_match} = $ctx->{rule_vars};
    }
    else {
        $ctx->{last_match} = undef;
    }

    $op_index = $ctx->{ok_return};
    $ctx->pop_saved if $op_index >= 0;
    return $op_index;
}

sub pkg_return($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{match_status} = 1;
    if ($ctx->{set_match_value}) {
        my $node_pkg = $ctx->LITERAL_LIST->[$op_list->[$op_index + 1]];
        my $rule_vars = $ctx->{rule_vars};
        $ctx->{last_match} = $node_pkg->new (%{$rule_vars || {}});
    }
    else {
        $ctx->{last_match} = undef;
    }

    $op_index = $ctx->{ok_return};
    $ctx->pop_saved if $op_index >= 0;
    return $op_index;
}

sub fail_return($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{match_status} = undef;
    $ctx->{last_match} = undef;

    $op_index = $ctx->{fail_return};
    $ctx->pop_saved if $op_index >= 0;
    return $op_index;
}

sub literal_test($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $text_ref = $ctx->{text_ref};
    my $cmp_str = $ctx->{LITERAL_LIST}->[$op_list->[$op_index + 1]];
    my $offset = pos ($$text_ref);
    if (
        $offset < length ($$text_ref) &&
        substr ($$text_ref, $offset, length ($cmp_str)) eq $cmp_str
    ) {
        pos ($$text_ref) = $offset + length ($cmp_str);
        $ctx->{match_status} = 1;
    }
    else {
        $ctx->{match_status} = undef;
    }
    return $op_index + 2;
}

sub literal_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $text_ref = $ctx->{text_ref};
    my $cmp_str = $ctx->{LITERAL_LIST}->[$op_list->[$op_index + 1]];
    my $offset = pos ($$text_ref);
    if (
        $offset < length ($$text_ref) &&
        substr ($$text_ref, $offset, length ($cmp_str)) eq $cmp_str
    ) {
        pos ($$text_ref) = $offset + length ($cmp_str);
        $ctx->{last_match} = $cmp_str;
        $ctx->{match_status} = 1;
    }
    else {
        $ctx->{last_match} = undef;
        $ctx->{match_status} = undef;
    }
    return $op_index + 2;
}

sub regex_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    die "generic regex op unsupported";
}

sub token_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    die "generic token op unsupported";
}

sub rule_test($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->push_and_init;
    $ctx->{ok_return} = $op_list->[$op_index + 2];
    $ctx->{fail_return} = $op_list->[$op_index + 3];
    $ctx->{set_match_value} = 0;
    return $op_list->[$op_index + 1];
}

sub rule_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->push_and_init;
    $ctx->{ok_return} = $op_list->[$op_index + 2];
    $ctx->{fail_return} = $op_list->[$op_index + 3];
    $ctx->{set_match_value} = 1;
    return $op_list->[$op_index + 1];
}

sub _init_registers($$$) {
    my ($ctx, $caller_registers, $reg_numbers) = @_;
    $caller_registers ||= [];
    my $i = 0;
    for (@$reg_numbers) {
        $ctx->register ($i++, $caller_registers->[$_]);
    }
}

sub rule_call_test($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $caller_registers = $ctx->registers;
    $ctx->push_and_init;
    $ctx->{ok_return} = $op_list->[$op_index + 2];
    $ctx->{fail_return} = $op_list->[$op_index + 3];
    $ctx->{set_match_value} = 0;
    # must be done after the push
    _init_registers ($ctx, $caller_registers, $op_list->[$op_index + 4]);
    return $op_list->[$op_index + 1];
}

sub rule_call($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $caller_registers = $ctx->registers;
    $ctx->push_and_init;
    $ctx->{ok_return} = $op_list->[$op_index + 2];
    $ctx->{fail_return} = $op_list->[$op_index + 3];
    $ctx->{set_match_value} = 1;
    # must be done after the push
    _init_registers ($ctx, $caller_registers, $op_list->[$op_index + 4]);
    return $op_list->[$op_index + 1];
}

sub custom_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    die "generic custom match op unsupported";
}

sub test_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    return $op_list->[
        $op_index + ($ctx->{match_status} ? 1 : 2)
    ];
}

sub not_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    $ctx->{match_status} = !($ctx->{match_status});
    return $op_list->[
        $op_index + ($ctx->{match_status} ? 1 : 2)
    ];
}

sub if_test($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $var_refs = $op_list->[$op_index + 3];
    $ctx->{match_status} = 1;
    for (@$var_refs) {
        $ctx->{match_status} = undef unless _var_get ($ctx, $_);
    }
    return $op_list->[
        $op_index + ($ctx->{match_status} ? 1 : 2)
    ];
}

sub jump_ok($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    return $ctx->{match_status} ?
        $op_list->[$op_index + 1] : $op_index + 2;
}

sub jump_fail($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    return !$ctx->{match_status} ?
        $op_list->[$op_index + 1] : $op_index + 2;
}

sub jump($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    return $op_list->[$op_index + 1];
}

sub var_set_const($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $v = $op_list->[$op_index + 3];

    # make copies from the const ref
    if (ref ($v) eq 'HASH')     { $v = {} }
    elsif (ref ($v) eq 'ARRAY') { $v = [] }

    _var_set (
        $ctx,
        $op_list->[$op_index + 1],
        $op_list->[$op_index + 2],
        $v
    );
    return $op_index + 4;
}

sub var_set_op($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    _var_set (
        $ctx,
        $op_list->[$op_index + 1],
        $op_list->[$op_index + 2],
        $ctx->{match_status} ? $ctx->{last_match} : undef
    );
    return $op_index + 3;
}

sub var_move($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $var_name_index = $op_list->[$op_index + 3];
    _var_set (
        $ctx,
        $op_list->[$op_index + 1],
        $op_list->[$op_index + 2],
        _var_get ($ctx, $ctx->{LITERAL_LIST}->[$var_name_index])
    );
    return $op_index + 4;
}

sub set_bt($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $text_ref = $ctx->{text_ref};
    my $slot     = $op_list->[$op_index + 1];
    $ctx->{bt_slots}->[$slot] = pos ($$text_ref);
    return $op_index + 2;
}

sub goto_bt($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $text_ref = $ctx->{text_ref};
    my $slot     = $op_list->[$op_index + 1];
    pos ($$text_ref) = $ctx->{bt_slots}->[$slot];
    return $op_index + 2;
}

sub set_iter_slot($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $slot  = $op_list->[$op_index + 1];
    my $value = $op_list->[$op_index + 2];
    $ctx->{bt_slots}->[$slot] = $value;
    return $op_index + 3;
}

sub add_iter_slot($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $slot  = $op_list->[$op_index + 1];
    my $value = $op_list->[$op_index + 2];
    $ctx->{bt_slots}->[$slot] += $value;
    return $op_index + 3;
}

sub gt_iter_slot($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $slot  = $op_list->[$op_index + 1];
    my $value = $op_list->[$op_index + 2];
    return ($ctx->{match_status} = $ctx->{bt_slots}->[$slot] > $value) ?
        $op_list->[$op_index + 3] : $op_list->[$op_index + 4];
}

sub key_match($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $key_lens  = $op_list->[$op_index + 1];
    my $match_map = $op_list->[$op_index + 2];

    my $text_ref = $ctx->{text_ref};
    my $offset   = pos ($$text_ref);
    my $max_key = substr ($$text_ref, $offset, $key_lens->[0]);

    my ($key_len, $match_idx);
    for (@$key_lens) {
        $key_len = $_;
        $match_idx   = $match_map->{substr ($max_key, 0, $_)};
        if (defined $match_idx) {
            $ctx->{match_status} = 1;
            return $match_idx;
        }
    }

    $ctx->{match_status} = undef;
    $ctx->{last_match}   = undef;
    return $op_list->[$op_index + 3];
}

#-------------------------------------------------------------------------------
# Infix Expression Parsing Ops
#-------------------------------------------------------------------------------

# maintain invariant: op precedence is non-decreasing from 0 .. n
# on the expression parts stack.

# op info is a four element array:
sub OP_TEXT_IDX()           { 0 }
sub OP_PRECEDENCE_IDX()     { 1 }
sub OP_ASSOC_IDX()          { 2 }
sub OP_CONSTRUCTOR_IDX()    { 3 }
sub OP_WORD_MODE_IDX()      { 4 }

sub _make_expr_subtree($$$$$$$) {
    my ($ctx, $op_index, $op_list, $left, $op_info, $right, $stack) = @_;
    if ($op_info->[OP_ASSOC_IDX] > 0) {
        # right associative -- swap left and right
        # to make a left-to-right post-order tree traversal
        # evaluate nodes in the correct order
        my $tmp = $left;
        $left   = $right;
        $right  = $tmp;
    }

    if (my $constructor = $op_info->[OP_CONSTRUCTOR_IDX]) {
        my $registers = $ctx->{registers};
        @$registers[0..4] = ( $left, $op_info->[OP_TEXT_IDX], $right, $op_info->[OP_PRECEDENCE_IDX], $op_info->[OP_ASSOC_IDX] );
        if ($constructor->($ctx, $op_index, $op_list) < 0) {
            $ctx->{error_message} ||= 'expression subtree constructor error:' . _parse_position_ident ($ctx);
            return undef;
        }
        return $ctx->{last_match};
    }

    return {
        left_arg    => $left,
        operator    => $op_info->[OP_TEXT_IDX],
        right_arg   => $right,
    };
}

sub _expr_tree($$$$$) {
    my ($ctx, $op_index, $op_list, $precedence, $stack) = @_;
    my $registers = $ctx->{registers};
    my @saved_r0_r4 = @$registers[0..4];

    while (3 < @$stack && $precedence < $stack->[-3]) {
        if (
            $stack->[-3] > $stack->[-6] ||      # tos operator is higher precedence than predecessor
            $stack->[-2]->[OP_ASSOC_IDX] > 0    # equal prcedence, right associative
        ) {
            my $right   = pop @$stack;
            my $op_info = pop @$stack;
                          pop @$stack;
            my $left    = pop @$stack;

            my $expr = _make_expr_subtree (
                $ctx, $op_index, $op_list, $left, $op_info, $right, $stack
            );
            return undef unless $expr;

            push @$stack, $expr;
            next;
        }

        # left associative and equal precedence ops
        # NOTE: depending on the left-most value ($stack->[0..2]) having
        #       a precedence lower than any real operator's precedence
        my $n = scalar (@$stack);
        my $start = -3; # top operator precedence
        while ($start - 3 > -$n && $stack->[$start - 3] == $stack->[-3]) {
            $start -= 3; # move down the stack (leftward in operator sequence)
        }
        my $expr = _make_expr_subtree (
            $ctx, $op_index, $op_list, 
            $stack->[$start - 1], $stack->[$start + 1], $stack->[$start + 2], $stack
        );
        return undef unless $expr;

        for (my $i=$start+3; $i<0; $i+=3) {
            $expr = _make_expr_subtree (
                $ctx, $op_index, $op_list, 
                $expr, $stack->[$i + 1], $stack->[$i + 2], $stack
            );
            return undef unless $expr;
        }
        splice (@$stack, $start);
        $stack->[-1] = $expr;
    }

    @$registers[0..4] = @saved_r0_r4;
    return 1;
}

sub expr_op($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    my $op_table = $op_list->[$op_index + 1];
    my $op_lens  = $op_table->{' op_len '};

    # expecting operator lengths to be in descending order
    my $text_ref = $ctx->{text_ref};
    my $offset = pos ($$text_ref);
    my $chars = substr ($$text_ref, $offset, $op_lens->[0]);

    my ($op_len, $op_info);
    for (my $i=0; $i<@$op_lens; $i++) {
        $op_len = $op_lens->[$i];
        $op_info = $op_table->{substr ($chars, 0, $op_len)};
        last if $op_info;
    }

    if (!$op_info ||
        $op_info->[OP_WORD_MODE_IDX] &&
            $offset + $op_len < length ($$text_ref) &&
            substr ($$text_ref, $offset + $op_len, 1) =~ m/[_a-zA-Z0-9]/
    ) {
        $ctx->{match_status} = undef;
        $ctx->{last_match}   = undef;
        return $op_index + 2;
    }

    # r5 is the expression stack:
    # [
    #    -1                    undef            expr-tree 
    #    operator-precedence   operator-info    expr-tree
    #    operator-precedence   operator-info    expr-tree
    #    ...
    #    operator-precedence   operator-info    expr-tree   <<-- tos
    # ]
    pos ($$text_ref) = $offset + $op_len;
    my $r5 = $ctx->register (5) ||
             $ctx->register (5, []);
    push @$r5, -1, undef, $ctx->register (0) unless @$r5;
    _expr_tree ($ctx, $op_index, $op_list, $op_info->[OP_PRECEDENCE_IDX], $r5);
    push @$r5, $op_info->[OP_PRECEDENCE_IDX], $op_info;

    $ctx->{match_status} = 1;
    return $op_index + 2;
}

sub expr_op_right_arg($$$) {
    my ($ctx, $op_index, $op_list) = @_;
    push @{$ctx->register (5)}, $ctx->register (1);
    $ctx->{match_status} = 1;
    return $op_index + 1;
}

sub expr_tree($$$) {
    my ($ctx, $op_index, $op_list) = @_;

    my $r5 = $ctx->register (5);
    _expr_tree ($ctx, $op_index, $op_list, -2, $r5);

    $ctx->{match_status} = 1;
    $ctx->{last_match} = $r5->[2];
    return $op_index + 1;
}

#-------------------------------------------------------------------------------

sub _set_trace($@) {
    my ($op_def, @flags) = @_;
    my $f = 0;
    for (@flags) { $f |= trace_flags_from_str ($_) };
    $op_def->set_trace_flags ($f);
    return $op_def;
}

sub _mk_op_def($$$@) {
    my ($op_type, $op_func, $trace_flags, @arg_types) = @_;
    my @arg_names;
    for (my $i=0; $i<@arg_types; $i++) {
        $arg_types[$i] =~ m/^(([^:]*)[:])?(.*)/;
        $arg_types[$i] = $3;
        $arg_names[$i] = $2 || '$' . $i;
    }
    my @trace_flags;
    @trace_flags = ( 'DETAIL', ref ($trace_flags) ? @$trace_flags : $trace_flags )
        if defined $trace_flags;
    return _set_trace (
        WW::Parse::PDA::OpDef->new (
            op_type => $op_type,
            op_func => $op_func,
            (@arg_types ? ( arg_types => \@arg_types, arg_names => \@arg_names ) : ( ))
        ),
        @trace_flags,
    );
}

our @_OP_DEFS;
our @_OP_FUNCS_EXPORTS;
BEGIN {
    return if @_OP_DEFS;
    @_OP_DEFS = (
        _mk_op_def ('debug_break_op',   \&debug_break_op,   'MATCH',            'msg:Str'),
        _mk_op_def ('trace_flags',      \&trace_flags,      'DETAIL',           'flags:Int'),

        _mk_op_def ('fail',             \&fail,             'MATCH',            ),
        _mk_op_def ('fatal',            \&fatal,            [qw( RULE MATCH )], 'msg_params:ArrayRef'),

        _mk_op_def ('rule_start',       \&rule_start,       'RULE',             'rule_name:Str', 'slot_count:Int'),
        _mk_op_def ('set_rule_vars',    \&set_rule_vars,    'RULE',             'rule_vars:HashRef'),
        _mk_op_def ('pkg_return',       \&pkg_return,       'RULE',             'pkg:Str'),
        _mk_op_def ('hash_return',      \&hash_return,      'RULE',             ),
        _mk_op_def ('ok_return',        \&ok_return,        'RULE',             ),
        _mk_op_def ('fail_return',      \&fail_return,      'RULE',             ),

        _mk_op_def ('literal_test',     \&literal_test,     'MATCH',            'text:Str'),
        _mk_op_def ('literal_match',    \&literal_match,    'MATCH',            'text:Str'),
        _mk_op_def ('regex_match',      \&regex_match,      'MATCH',            'regex:Regex'),
        _mk_op_def ('token_match',      \&token_match,      'MATCH',            'set_match:Int'),
        _mk_op_def ('rule_test',        \&rule_test,        'MATCH',            'rule:RuleIndex', 'ok:OpIndex', 'fail:OpIndex'),
        _mk_op_def ('rule_match',       \&rule_match,       'MATCH',            'rule:RuleIndex', 'ok:OpIndex', 'fail:OpIndex'),
        _mk_op_def ('rule_call_test',   \&rule_call_test,   'MATCH',            'rule:RuleIndex', 'ok:OpIndex', 'fail:OpIndex', 'reg_numbers:ArrayRef'),
        _mk_op_def ('rule_call',        \&rule_call,        'MATCH',            'rule:RuleIndex', 'ok:OpIndex', 'fail:OpIndex', 'reg_numbers:ArrayRef'),
        _mk_op_def ('custom_match',     \&custom_match,     'MATCH',            'match_args:ArrayRef'),
        _mk_op_def ('expr_op',          \&expr_op,          'MATCH',            'op_table_name:OpTableName'),
        _mk_op_def ('expr_op_right_arg',\&expr_op_right_arg,'MATCH',            ),
        _mk_op_def ('expr_tree',        \&expr_tree,        'MATCH',            ),
        _mk_op_def ('key_match',        \&key_match,        'MATCH',            'key_lengths:IntArray', 'match_map:OpIndexMap', 'fail:OpIndex'),

        _mk_op_def ('test_match',       \&test_match,       'MATCH',            'ok:OpIndex', 'fail:OpIndex'),
        _mk_op_def ('not_match',        \&not_match,        'MATCH',            'ok:OpIndex', 'fail:OpIndex'),
        _mk_op_def ('if_test',          \&if_test,          'MATCH',            'ok:OpIndex', 'fail:OpIndex', 'var_refs:ArrayRef'),
        _mk_op_def ('jump_ok',          \&jump_ok,          'MATCH',            'next:OpIndex'),
        _mk_op_def ('jump_fail',        \&jump_fail,        'MATCH',            'next:OpIndex'),
        _mk_op_def ('jump',             \&jump,             'DETAIL',           'next:OpIndex'),

        _mk_op_def ('var_set_const',    \&var_set_const,    'MATCH',            'var_name:Str', 'set_op:SetOp', 'value:Any'),
        _mk_op_def ('var_set_op',       \&var_set_op,       'MATCH',            'var_name:Str', 'set_op:SetOp'),
        _mk_op_def ('var_move',         \&var_move,         'MATCH',            'var_name:Str', 'set_op:SetOp', 'src_name:Str'),

        # TODO: just convert to one set of int slots for both backtracking nad iteration counting

        _mk_op_def ('set_bt',           \&set_bt,           'BT',               'slot_idx:Int'),
        _mk_op_def ('goto_bt',          \&goto_bt,          'BT',               'slot_idx:Int'),

        _mk_op_def ('set_iter_slot',    \&set_iter_slot,    'BT',               'slot_idx:Int', 'value:Int'),
        _mk_op_def ('add_iter_slot',    \&add_iter_slot,    'BT',               'slot_idx:Int', 'value:Int'),
        _mk_op_def ('gt_iter_slot',     \&gt_iter_slot,     'BT',               'iter_slot:Int', 'value:Int', 'ok:OpIndex', 'fail:OpIndex'),
    );

    @_OP_FUNCS_EXPORTS = map { $_->op_type } @_OP_DEFS;
    push @_OP_FUNCS_EXPORTS, 'dump_ctx';
}

sub get_op_defs { \@_OP_DEFS }

#-------------------------------------------------------------------------------

use Exporter qw( import );

our @_CUSTOM_OP_HELPERS = qw( _parse_position_ident _fatal_error_msg );

our @EXPORT_OK = (
    qw( PDA_ENGINE_VERSION get_op_defs ),
    @_OP_FUNCS_EXPORTS,
    @_CUSTOM_OP_HELPERS,
);

our %EXPORT_TAGS = ( 
    all         => \@EXPORT_OK,
    op_funcs    => \@_OP_FUNCS_EXPORTS,
    op_helpers  => \@_CUSTOM_OP_HELPERS,
);

1;

