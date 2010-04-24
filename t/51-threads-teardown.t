#!perl

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
  plan tests => 1;
  defined and diag "Using threads $_" for $threads::VERSION;
 } else {
  plan skip_all => 'This autovivification isn\'t thread safe';
 }
}

sub run_perl {
 my $code = shift;

 my $SystemRoot   = $ENV{SystemRoot};
 local %ENV;
 $ENV{SystemRoot} = $SystemRoot if $^O eq 'MSWin32' and defined $SystemRoot;

 system { $^X } $^X, '-T', map("-I$_", @INC), '-e', $code;
}

SKIP:
{
 skip 'Fails on 5.8.2 and lower' => 1 if $] <= 5.008002;

 my $status = run_perl <<' RUN';
  my $code = 1 + 2 + 4;
  use threads;
  $code -= threads->create(sub {
   eval q{no autovivification; my $x; my $y = $x->{foo}; $x};
   return defined($x) ? 0 : 1;
  })->join;
  $code -= defined(eval q{my $x; my $y = $x->{foo}; $x}) ? 2 : 0;
  $code -= defined(eval q{no autovivification; my $x; my $y = $x->{foo}; $x})
           ? 0 : 4;
  exit $code;
 RUN
 is $status, 0, 'loading the pragma in a thread and using it outside doesn\'t segfault';
}
