#!perl -T

use strict;
use warnings;

use Test::More tests => 4;

use lib 't/lib';

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

