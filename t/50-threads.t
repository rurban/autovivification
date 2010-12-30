#!perl -T

use strict;
use warnings;

sub skipall {
 my ($msg) = @_;
 require Test::More;
 Test::More::plan(skip_all => $msg);
}

use Config qw/%Config/;

BEGIN {
 my $force = $ENV{PERL_AUTOVIVIFICATION_TEST_THREADS} ? 1 : !1;
 skipall 'This perl wasn\'t built to support threads'
                                                    unless $Config{useithreads};
 skipall 'perl 5.13.4 required to test thread safety'
                                                unless $force or $] >= 5.013004;
}

use threads;

use Test::More;

BEGIN {
 require autovivification;
 skipall 'This autovivification isn\'t thread safe'
                                        unless autovivification::A_THREADSAFE();
}

my ($threads, $runs);
BEGIN {
 $threads = 10;
 $runs    = 2;
}

BEGIN {
 plan tests => $threads * $runs * 3 * (1 + 2);
 defined and diag "Using threads $_" for $threads::VERSION;
}

{
 no autovivification;

 sub try {
  my $tid = threads->tid();

  for my $run (1 .. $runs) {
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

my @t = map threads->create(\&try), 1 .. $threads;
$_->join for @t;
