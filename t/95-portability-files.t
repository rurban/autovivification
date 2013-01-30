#!perl -T

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

load_or_skip_all('Test::Portability::Files', undef, [ ]);

run_tests();
