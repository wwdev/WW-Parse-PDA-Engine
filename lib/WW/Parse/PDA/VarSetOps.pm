package WW::Parse::PDA::VarSetOps;
use feature qw(:5.12);
use strict;

our $VERSION = '0.03';

sub VAR_SET_OP_SET()        { 0 }
sub VAR_SET_OP_SETIF()      { 1 }
sub VAR_SET_OP_APPEND()     { 2 }
sub VAR_SET_OP_A_APPEND()   { 3 }
sub VAR_SET_OP_FA_APPEND()  { 4 }

sub PDA_VAR_REGISTER()      { 0 }
sub PDA_VAR_OFFSET()        { 1 }
sub PDA_VAR_MATCH()         { 2 }
sub PDA_VAR_RULE_VAR()      { 3 }
sub PDA_VAR_RULE_VARS()     { 4 }
sub PDA_VAR_CONST()         { 5 }
sub PDA_VAR_MAX()           { 5 }

our @_SET_OPS;
our %_SET_OPS;
our @_PDA_VARS;
our %_PDA_VARS;

BEGIN {
    return if @_SET_OPS;
    my @kv = (
        VAR_SET_OP_SET,          '=',
        VAR_SET_OP_SETIF,        '?=',
        VAR_SET_OP_APPEND,       '+=',
        VAR_SET_OP_A_APPEND,     '<<',
        VAR_SET_OP_FA_APPEND,    '<<<',
    );
    while (@kv) {
        my $code = shift @kv;
        my $str  = shift @kv;
        $_SET_OPS[$code] = $str;
        $_SET_OPS{$str} = $code;
    }

    @kv = (
        PDA_VAR_REGISTER,       '$$r',
        PDA_VAR_OFFSET,         '$$offset',
        PDA_VAR_MATCH,          '$$',
        PDA_VAR_RULE_VAR,       '$',
        PDA_VAR_RULE_VARS,      '$$rule_vars',
        PDA_VAR_CONST,          '$$const',
    );
    while (@kv) {
        my $code = shift @kv;
        my $str  = shift @kv;
        $_PDA_VARS[$code] = $str;
        $_PDA_VARS{$str} = $code;
    }
}

#-------------------------------------------------------------------------------

sub var_set_op_to_str($) {
    my $op_code = $_[0];
    return '<OP:undef>' unless defined $op_code;
    return '<OP:"' . $op_code . '">' unless $op_code =~ /^[0-9]+$/;
    if (my $str = $_SET_OPS[int ($op_code)]) {
        return $str;
    }
#say STDERR "**************** var_set_op_to_str <$op_code> ****************************";
    return "<OP:$op_code>";
}

sub var_set_op_from_str($) {
    my $op_str = $_[0] || '';
    my $op_code = $_SET_OPS{$op_str};
    return $op_code if defined $op_code;
    die "unknown VAR_SET_OP op string: $op_str";
}

#-------------------------------------------------------------------------------

sub pda_var_spec_to_str($;$) {
    my ($var_type, $ident) = @_;
    return '<VAR:undef>' unless defined $var_type;
    return '<VAR:"' . $var_type . '">' unless $var_type =~ /^[0-9]+$/;

    my $str = $_PDA_VARS[int ($var_type)];
    return '<VAR:"' . $var_type . '">' unless $var_type;

    return $var_type == PDA_VAR_REGISTER ? ($str . (defined ($ident) ? $ident : '?')) :
           $var_type == PDA_VAR_RULE_VAR ? ($str . ($ident || '???')) :
                        $str;
}

sub pda_var_spec_from_str($) {
    my $spec_str = $_[0];
    die ("var spec string is undef or empty")
        unless defined ($spec_str) && length ($spec_str);

    for (PDA_VAR_OFFSET, PDA_VAR_MATCH, PDA_VAR_RULE_VARS ) {
        return ( $_ ) if $spec_str eq $_PDA_VARS[$_];
    }
    if ($spec_str =~ m/^[\$][\$]r(\d)$/) {
        return ( PDA_VAR_REGISTER, int ($1) )
    }
    if ($spec_str =~ m/^[\$](\w+)$/) {
        return ( PDA_VAR_RULE_VAR, $1 )
    }
    die ("invalid var spec: $spec_str");
}

#-------------------------------------------------------------------------------

use Exporter qw( import );

our @_OP_CONSTS_EXPORTS = qw(
    VAR_SET_OP_SET VAR_SET_OP_SETIF VAR_SET_OP_APPEND VAR_SET_OP_A_APPEND VAR_SET_OP_FA_APPEND
    PDA_VAR_REGISTER PDA_VAR_OFFSET PDA_VAR_MATCH PDA_VAR_RULE_VAR PDA_VAR_RULE_VARS
);
our @_OP_FUNCS_EXPORTS = qw( 
    var_set_op_to_str       var_set_op_from_str 
    pda_var_spec_to_str 
);
our @EXPORT_OK = ( @_OP_CONSTS_EXPORTS, @_OP_FUNCS_EXPORTS );

our %EXPORT_TAGS = ( 
    all         => \@EXPORT_OK,
    op_funcs    => \@_OP_FUNCS_EXPORTS,
    op_consts   => \@_OP_CONSTS_EXPORTS,
);

1;

