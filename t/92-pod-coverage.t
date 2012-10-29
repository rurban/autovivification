#!perl -T

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

my $desc = 'required for testing POD coverage';

load_or_skip('Test::Pod::Coverage', '1.08', [ ],   $desc);
load_or_skip('Pod::Coverage',       '0.18', undef, $desc);

eval 'use Test::Pod::Coverage'; # Make Kwalitee test happy

all_pod_coverage_ok({ also_private => [ qr/^A_HINT_/ ] });
