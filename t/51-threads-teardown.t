#!perl

use strict;
use warnings;

use lib 't/lib';
use autovivification::TestThreads;

use Test::Leaner tests => 1;

sub run_perl {
 my $code = shift;

 my ($SystemRoot, $PATH) = @ENV{qw<SystemRoot PATH>};
 local %ENV;
 $ENV{SystemRoot} = $SystemRoot if $^O eq 'MSWin32' and defined $SystemRoot;
 $ENV{PATH}       = $PATH       if $^O eq 'cygwin'  and defined $PATH;

 system { $^X } $^X, '-T', map("-I$_", @INC), '-e', $code;
}

SKIP:
{
 skip 'Fails on 5.8.2 and lower' => 1 if "$]" <= 5.008_002;

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
