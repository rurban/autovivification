#!perl -T

use strict;
use warnings;

use lib 't/lib';
use Test::Leaner tests => 4 * 4 * (8 ** 3) * 2;

my $depth = 3;

my $magic_val = 123;

my @prefixes = (
 sub { $_[0]                },
 sub { "$_[0] = $magic_val" },
 sub { "exists $_[0]"       },
 sub { "delete $_[0]"       },
);

my  (@vlex, %vlex, $vrlex);
our (@vgbl, %vgbl, $vrgbl);

my @heads = (
 '$vlex',    # lexical array/hash
 '$vgbl',    # global array/hash
 '$vrlex->', # lexical array/hash reference
 '$vrgbl->', # global array/hash reference
);

my  $lex;
our $gbl;

my @derefs = (
 '[0]',      # array const (aelemfast)
 '[$lex]',   # array lexical
 '[$gbl]',   # array global
 '[$lex+1]', # array complex
 '{foo}',    # hash const
 '{$lex}',   # hash lexical
 '{$gbl}',   # hash global
 '{"x$lex"}' # hash complex
);

sub reset_vars {
 (@vlex, %vlex, $vrlex) = ();
 (@vgbl, %vgbl, $vrgbl) = ();
 $lex = 1;
 $gbl = 2;
}

{
 package autovivification::TestIterator;

 sub new {
  my $class = shift;

  my $len = @_;
  bless {
   len => $len,
   max => \@_,
   idx => [ (0) x $len ],
  }, $class;
 }

 sub next {
  my $self = shift;

  my ($len, $max, $idx) = @$self{qw<len max idx>};

  my $i;
  ++$idx->[0];
  for ($i = 0; $i < $len; ++$i) {
   if ($idx->[$i] == $max->[$i]) {
    $idx->[$i] = 0;
    ++$idx->[$i + 1] unless $i == $len - 1;
   } else {
    last;
   }
  }

  return $i < $len;
 }

 sub pick {
  my $self = shift;

  my ($len, $idx) = @$self{qw<len idx>};

  return map $_[$_]->[$idx->[$_]], 0 .. ($len - 1);
 }
}

my $iterator = autovivification::TestIterator->new(4, 4, (8) x $depth);
do {
 my ($prefix, @elems)
                    = $iterator->pick(\@prefixes, \@heads, (\@derefs) x $depth);
 my $code = $prefix->(join '', @elems);
 my $exp  = ($code =~ /^\s*exists/) ? !1
                                    : (($code =~ /=\s*$magic_val/) ? $magic_val
                                                                   : undef);
 reset_vars();
 my ($res, $err) = do {
  local $SIG{__WARN__} = sub { die @_ };
  local $@;
  my $r = eval <<" CODE";
  no autovivification;
  $code
 CODE
  ($r, $@)
 };
 is $err, '',   "$code: no exception";
 is $res, $exp, "$code: value";
} while ($iterator->next);
