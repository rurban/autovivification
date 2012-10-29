#!perl

use strict;
use warnings;

use Test::More;

use lib 't/lib';
use VPIT::TestHelpers;

my $guard = VPIT::TestHelpers::Guard->new(
 sub { unlink for glob 'Debian_CPANTS.txt*' }
);

my $desc = 'required to test kwalitee';

load_or_skip('Parse::RecDescent',  '1.967006', undef, $desc);
load_or_skip('Module::ExtractUse', '0.24',     undef, $desc);
load_or_skip('Test::Kwalitee',     '1.01',     undef, $desc);

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
