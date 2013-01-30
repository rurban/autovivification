#!perl -T

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

load_or_skip_all('Test::Pod', '1.22', [ ]);

eval 'use Test::Pod'; # Make Kwalitee test happy

all_pod_files_ok();
