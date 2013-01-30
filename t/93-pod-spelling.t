#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

load_or_skip_all('Test::Pod::Spelling::CommonMistakes', '1.0', [ ]);

all_pod_files_ok();
