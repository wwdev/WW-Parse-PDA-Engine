#!perl
use feature qw(:5.12);
use strict;
use warnings FATAL => 'all';
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

plan tests => 8;

BEGIN {
    use_ok( 'WW::Parse::PDA::Engine' );
    use_ok( 'WW::Parse::PDA::ExecCtx' );
    use_ok( 'WW::Parse::PDA::OpDef' );
    use_ok( 'WW::Parse::PDA::OpDefs' );
    use_ok( 'WW::Parse::PDA::ParserBase' );
    use_ok( 'WW::Parse::PDA::Trace' );
    use_ok( 'WW::Parse::PDA::TraceConsts' );
    use_ok( 'WW::Parse::PDA::VarSetOps' );
}

diag( "Testing WW::Parse::PDA::Engine $WW::Parse::PDA::Engine::VERSION, Perl $], $^X" );

