#!perl -T

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

load_or_skip('Test::Pod::Spelling::CommonMistakes', '1.0', [ ],
             'required for testing POD spelling');

all_pod_files_ok();
