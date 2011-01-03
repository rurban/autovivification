#!perl -T

use strict;
use warnings;

use Test::More;

if (eval 'use B::Deparse; 1') {
 plan tests => 2;
} else {
 plan skip_all => 'B::Deparse is not available';
}

my $bd = B::Deparse->new;

{
 no autovivification qw<fetch strict>;

 sub blech { my $key = $_[0]->{key} }
}

{
 my $undef;
 eval 'blech($undef)';
 like $@, qr/Reference vivification forbidden/, 'Original blech() works';
}

{
 my $code = $bd->coderef2text(\&blech);
 my $undef;
 eval "$code; blech(\$undef)";
 like $@, qr/Reference vivification forbidden/, 'Deparsed blech() works';
}
