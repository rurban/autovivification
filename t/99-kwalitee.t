#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

my $guard = VPIT::TestHelpers::Guard->new(
 sub { unlink for glob 'Debian_CPANTS.txt*' }
);

load_or_skip_all('Parse::RecDescent',  '1.967006');
load_or_skip_all('Module::ExtractUse', '0.24'    );
load_or_skip_all('Test::Kwalitee',     '1.01'    );

SKIP: {
 eval { Test::Kwalitee->import(); };
 if (my $err = $@) {
  1 while chomp $err;
  require Test::Builder;
  my $Test = Test::Builder->new;
  my $plan = $Test->has_plan;
  $Test->skip_all($err) if not defined $plan or $plan eq 'no_plan';
  skip $err => $plan - $Test->current_test;
 }
}
