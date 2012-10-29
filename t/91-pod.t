#!perl -T

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

load_or_skip('Test::Pod', '1.22', [ ],
             'required for testing POD syntax');

eval 'use Test::Pod'; # Make Kwalitee test happy

all_pod_files_ok();
