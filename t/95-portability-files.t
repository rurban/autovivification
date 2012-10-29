#!perl -T

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

load_or_skip('Test::Portability::Files', undef, [ ],
             'required for testing filenames portability');

run_tests();
