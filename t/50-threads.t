#!perl -T

use strict;
use warnings;

use Config qw/%Config/;

BEGIN {
 if (!$Config{useithreads}) {
  require Test::More;
  Test::More->import;
  plan(skip_all => 'This perl wasn\'t built to support threads');
 }
}

use threads;

use Test::More;

BEGIN {
 require autovivification;
 if (autovivification::A_THREADSAFE()) {
  plan tests => 10 * 2 * 3 * (1 + 2);
  defined and diag "Using threads $_" for $threads::VERSION;
 } else {
  plan skip_all => 'This autovivification isn\'t thread safe';
 }
}

{
 no autovivification;

 sub try {
  my $tid = threads->tid();

  for my $run (1 .. 2) {
   {
    my $x;
    my $y = $x->{foo};
    is $x, undef, "fetch does not autovivify at thread $tid run $run";
   }
   {
    my $x;
    my $y = exists $x->{foo};
    is $x, undef, "exists does not autovivify at thread $tid run $run";
   }
   {
    my $x;
    my $y = delete $x->{foo};
    is $x, undef, "delete does not autovivify at thread $tid run $run";
   }

SKIP:
   {
    skip 'Hints aren\'t propagated into eval STRING below perl 5.10' => 3 * 2
                                                             unless $] >= 5.010;
    {
     my $x;
     eval 'my $y = $x->{foo}';
     is $@, '',    "fetch in eval does not croak at thread $tid run $run";
     is $x, undef, "fetch in eval does not autovivify at thread $tid run $run";
    }
    {
     my $x;
     eval 'my $y = exists $x->{foo}';
     is $@, '',    "exists in eval does not croak at thread $tid run $run";
     is $x, undef, "exists in eval does not autovivify at thread $tid run $run";
    }
    {
     my $x;
     eval 'my $y = delete $x->{foo}';
     is $@, '',    "delete in eval does not croak at thread $tid run $run";
     is $x, undef, "delete in eval does not autovivify at thread $tid run $run";
    }
   }
  }
 }
}

my @t = map threads->create(\&try), 1 .. 10;
$_->join for @t;
