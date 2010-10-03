#!perl

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
 plan tests => 1;
 defined and diag "Using threads $_" for $threads::VERSION;
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
