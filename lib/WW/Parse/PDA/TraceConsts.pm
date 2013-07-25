package WW::Parse::PDA::TraceConsts;
use feature qw(:5.12);
use strict;

our $VERSION = '0.01';

sub TRACE_FLAGS_MATCH()        { 1 }
sub TRACE_FLAGS_RULE()         { 2 }
sub TRACE_FLAGS_BT()           { 4 }
sub TRACE_FLAGS_DETAIL()       { 8 }
sub TRACE_FLAGS_ALL()          { 15 }

our %_TRACE_FLAGS = (
    MATCH       => TRACE_FLAGS_MATCH,
    RULE        => TRACE_FLAGS_RULE,
    BT          => TRACE_FLAGS_BT,
    DETAIL      => TRACE_FLAGS_DETAIL,
);

sub trace_flags_to_str($) {
    my $trace_flags = $_[0];
    my @flags;
    while (my ($k, $v) = each (%_TRACE_FLAGS)) {
        if ($v & $trace_flags) { push @flags, $k; }
    }
    return join (' ', @flags);
}

sub trace_flags_from_str($) {
    my $trace_flags_str = $_[0] || '';
    $trace_flags_str =~ s/^\s+|\s+$//g;
    if ($trace_flags_str =~ m/^[-+]?\d+$/) {
        return int ($trace_flags_str);
    }

    my $trace_flags = 0;
    for (split (/[\s,]+/, uc ($trace_flags_str))) {
        return TRACE_FLAGS_ALL if $_ eq 'ALL';
        my $f = $_TRACE_FLAGS{$_};
        $trace_flags |= $f if defined $f;
        die ("unknown TRACE_FLAG: $_") unless defined $f;
    }
    return $trace_flags;
}

#-------------------------------------------------------------------------------

use Exporter qw( import );

our @_TRACECONSTS_EXPORTS = qw(
    TRACE_FLAGS_MATCH TRACE_FLAGS_RULE TRACE_FLAGS_BT TRACE_FLAGS_DETAIL TRACE_FLAGS_ALL
);
our @_TRACEFUNCS_EXPORTS = qw( trace_flags_to_str trace_flags_from_str );
our @EXPORT_OK = ( @_TRACECONSTS_EXPORTS, @_TRACEFUNCS_EXPORTS );

our %EXPORT_TAGS = ( 
    all             => \@EXPORT_OK,
    convert_funcs   => \@_TRACEFUNCS_EXPORTS,
    trace_flags     => \@_TRACECONSTS_EXPORTS,
);

1;

