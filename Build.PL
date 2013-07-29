use 5.012;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new (
    dist_name           => 'WW-Parse-PDA-Engine',
    module_name         => 'WW::Parse::PDA::Engine',
    dist_author         => q{Lee Woodworth <wwdev16@gmail.com>},
    dist_version        => '0.12.1',
    dist_abstract       => 'PDA-based parsing engine (runtime)',
    license             => 'Artistic_2_0',
    create_license      => 'Artistic_2_0',
    meta_merge          => {
        keywords        => [qw( parser pda )],
    },
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More'    => 0,
        'FindBin'       => 0,
    },
    requires => {
        'Scalar::Util'  => 0,
        'Moose'         => 0,
    },
    add_to_cleanup      => [ 'WW-Parse-PDA-Engine-*' ],
    create_makefile_pl  => 'traditional',
);

$builder->create_build_script ();

