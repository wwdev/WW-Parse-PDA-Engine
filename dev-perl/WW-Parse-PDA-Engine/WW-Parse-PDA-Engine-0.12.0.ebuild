# Copyright 2013 Lee Woodworth.
# Distributed under the terms of the GNU General Public License v2

EAPI="2"

MODULE_AUTHOR="WWDEV16"


inherit perl-module

DESCRIPTION="PDA-based parsing engine (runtime)"

LICENSE="|| ( Artistic GPL-1 GPL-2 GPL-3 )"
SLOT="0"
KEYWORDS="amd64"
IUSE=""

DEPEND="
	virtual/perl-Module-Build
	dev-lang/perl
	dev-perl/Moose
"

