#!perl -T

use strict;
use warnings;

use Test::More tests => 8;

use lib 't/lib';

{
 my @w;
 my $x;
 my $res = eval {
  local $SIG{__WARN__} = sub { push @w, join '', 'warn:', @_ };
  no autovivification qw/warn fetch/;
  $x->{a};
 };
 is   @w,    1,     'warned only once';
 like $w[0], qr/^warn:Reference was vivified at \Q$0\E line ${\(__LINE__-3)}/,
                        'warning looks correct';
 is_deeply $x,   undef, 'didn\'t vivified';
 is        $res, undef, 'returned undef';
}

our $blurp;

{
 local $blurp;
 eval 'no autovivification; use autovivification::TestRequired1; $blurp->{x}';
 is        $@,     '',          'first require test doesn\'t croak prematurely';
 is_deeply $blurp, { r1_main => { }, r1_eval => { } },
                                'first require vivified correctly';
}

{
 local $blurp;
 eval 'no autovivification; use autovivification::TestRequired2; $blurp->{a}'; 
 is        $@,     '',      'second require test doesn\'t croak prematurely';
 my $expect;
 $expect = { r1_main => { }, r1_eval => { } };
 $expect->{r2_eval} = { } if $] <  5.009005;
 is_deeply $blurp, $expect, 'second require test didn\'t vivify';
}
