#!perl -T

use strict;
use warnings;

use Test::More tests => 6 * 3 * 260;

sub testcase {
 my ($var, $init, $code, $exp, $use, $global) = @_;
 my $decl = $global ? "our $var; local $var;" : "my $var;";
 my $test = $var =~ /^[@%]/ ? "\\$var" : $var;
 return <<TESTCASE;
my \@exp = ($exp);
$decl
$init
my \$res = eval {
 local \$SIG{__WARN__} = sub { die join '', 'warn:', \@_ };
 $use
 $code
};
if (ref \$exp[0]) {
 like \$@, \$exp[0], \$desc . ' [exception]';
} else {
 is   \$@, \$exp[0], \$desc . ' [exception]';
}
is_deeply \$res, \$exp[1], \$desc . ' [return]';
is_deeply $test, \$exp[2], \$desc . ' [variable]';
TESTCASE
}

while (<DATA>) {
 1 while chomp;
 next unless /#/;
 my @chunks = split /#+/, "$_ ";
 s/^\s+//, s/\s+$// for @chunks;
 my ($init, $code, $exp, $opts) = @chunks;
 (my $var = $init) =~ s/[^\$@%\w].*//;
 $init = $var eq $init ? '' : "$init;";
 my $use;
 if ($opts) {
  for (split ' ', $opts) {
   my $no = 1;
   $no = 0 if s/^([-+])// and $1 eq '-';
   $use .= ($no ? 'no' : 'use') . " autovivification '$_';"
  }
 } elsif (defined $opts) {
  $opts = 'empty';
  $use  = 'no autovivification;';
 } else {
  $opts = 'default';
  $use  = '';
 }
 my @testcases = (
  [ $var, $init,               $code, $exp, $use, 0 ],
  [ $var, "use strict; $init", $code, $exp, $use, 1 ],
  [ $var, "no strict;  $init", $code, $exp, $use, 1 ],
 );
 my @extra;
 for (@testcases) {
  my $var = $_->[0];
  if ($var =~ /\$/) {
   my @new = @$_;
   $new[0] =~ s/^$/@/;
   $new[1] =~ s/$var\->/$var/g;
   $new[2] =~ s/$var\->/$var/g;
   push @extra, \@new;
  }
 }
 push @testcases, @extra;
 for (@testcases) {
  my $testcase = testcase(@$_);
  my ($var, $init, $code) = @$_;
  my $desc = do { (my $x = "$var | $init") =~ s,;\s+$,,; $x } . " | $code | $opts";
  eval $testcase;
  diag "== This testcase failed to compile ==\n$testcase\n## Reason: $@" if $@;
 }
}

__DATA__

--- fetch ---

$x # $x->[0] # '', undef, [ ]
$x # $x->[0] # '', undef, undef #
$x # $x->[0] # '', undef, undef # +fetch
$x # $x->[0] # '', undef, [ ] # +exists
$x # $x->[0] # '', undef, [ ] # +delete
$x # $x->[0] # '', undef, [ ] # +store

$x # $x->[0] # qr/^Reference vivification forbidden/, undef, undef # +strict +fetch
$x # $x->[0] # '', undef, [ ] # +strict +exists
$x # $x->[0] # '', undef, [ ] # +strict +delete
$x # $x->[0] # '', undef, [ ] # +strict +store

$x # $x->[0]->[1] # '', undef, [ [ ] ]
$x # $x->[0]->[1] # '', undef, undef #
$x # $x->[0]->[1] # '', undef, undef # +fetch
$x # $x->[0]->[1] # '', undef, [ [ ] ] # +exists
$x # $x->[0]->[1] # '', undef, [ [ ] ] # +delete
$x # $x->[0]->[1] # '', undef, [ [ ] ] # +store

$x # $x->[0]->[1] # qr/^Reference vivification forbidden/, undef, undef # +strict +fetch
$x # $x->[0]->[1] # '', undef, [ [ ] ] # +strict +exists
$x # $x->[0]->[1] # '', undef, [ [ ] ] # +strict +delete
$x # $x->[0]->[1] # '', undef, [ [ ] ] # +strict +store

$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +fetch
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +fetch
$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +exists
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +exists
$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +delete
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +delete
$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +store
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +store

$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +strict +fetch
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +strict +fetch
$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +strict +exists
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +strict +exists
$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +strict +delete
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +strict +delete
$x->[0] = 1 # $x->[0] # '', 1, [ 1 ] # +strict +store
$x->[0] = 1 # $x->[1] # '', undef, [ 1 ] # +strict +store

$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +fetch
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +fetch
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ] ] # +fetch
$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +exists
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +exists
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +exists
$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +delete
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +delete
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +delete
$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +store
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +store
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +store

$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +fetch
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +fetch
$x->[0]->[1] = 1 # $x->[2]->[3] # qr/^Reference vivification forbidden/, undef, [ [ undef, 1 ] ] # +strict +fetch
$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +exists
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +exists
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +strict +exists
$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +delete
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +delete
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +strict +delete
$x->[0]->[1] = 1 # $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +store
$x->[0]->[1] = 1 # $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +store
$x->[0]->[1] = 1 # $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +strict +store

--- aliasing ---

$x # 1 for $x->[0]; () # '', undef, [ undef ]
$x # 1 for $x->[0]; () # '', undef, undef #
$x # 1 for $x->[0]; () # '', undef, undef # +fetch
$x # 1 for $x->[0]; () # '', undef, [ undef ] # +exists
$x # 1 for $x->[0]; () # '', undef, [ undef ] # +delete
$x # 1 for $x->[0]; () # '', undef, [ undef ] # +store

$x # $_ = 1 for $x->[0]; () # '', undef, [ 1 ]
$x # $_ = 1 for $x->[0]; () # '', undef, undef #
$x # $_ = 1 for $x->[0]; () # '', undef, undef # +fetch
$x # $_ = 1 for $x->[0]; () # '', undef, [ 1 ] # +exists
$x # $_ = 1 for $x->[0]; () # '', undef, [ 1 ] # +delete
$x # $_ = 1 for $x->[0]; () # '', undef, [ 1 ] # +store

$x->[0] = 1 # 1 for $x->[0]; () # '', undef, [ 1 ] # +fetch
$x->[0] = 1 # 1 for $x->[1]; () # '', undef, [ 1, undef ] # +fetch
$x->[0] = 1 # 1 for $x->[0]; () # '', undef, [ 1 ] # +exists
$x->[0] = 1 # 1 for $x->[1]; () # '', undef, [ 1, undef ] # +exists
$x->[0] = 1 # 1 for $x->[0]; () # '', undef, [ 1 ] # +delete
$x->[0] = 1 # 1 for $x->[1]; () # '', undef, [ 1, undef ] # +delete
$x->[0] = 1 # 1 for $x->[0]; () # '', undef, [ 1 ] # +store
$x->[0] = 1 # 1 for $x->[1]; () # '', undef, [ 1, undef ] # +store

--- exists ---

$x # exists $x->[0] # '', '', [ ]
$x # exists $x->[0] # '', '', undef #
$x # exists $x->[0] # '', '', [ ] # +fetch
$x # exists $x->[0] # '', '', undef # +exists
$x # exists $x->[0] # '', '', [ ] # +delete
$x # exists $x->[0] # '', '', [ ] # +store

$x # exists $x->[0] # '', '', [ ] # +strict +fetch
$x # exists $x->[0] # qr/^Reference vivification forbidden/, undef, undef # +strict +exists
$x # exists $x->[0] # '', '', [ ] # +strict +delete
$x # exists $x->[0] # '', '', [ ] # +strict +store

$x # exists $x->[0]->[1] # '', '', [ [ ] ]
$x # exists $x->[0]->[1] # '', '', undef #
$x # exists $x->[0]->[1] # '', '', [ [ ] ] # +fetch
$x # exists $x->[0]->[1] # '', '', undef # +exists
$x # exists $x->[0]->[1] # '', '', [ [ ] ] # +delete
$x # exists $x->[0]->[1] # '', '', [ [ ] ] # +store

$x # exists $x->[0]->[1] # '', '', [ [ ] ] # +strict +fetch
$x # exists $x->[0]->[1] # qr/^Reference vivification forbidden/, undef, undef # +strict +exists
$x # exists $x->[0]->[1] # '', '', [ [ ] ] # +strict +delete
$x # exists $x->[0]->[1] # '', '', [ [ ] ] # +strict +store

$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +fetch
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +fetch
$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +exists
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +exists
$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +delete
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +delete
$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +store
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +store

$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +strict +fetch
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +strict +fetch
$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +strict +exists
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +strict +exists
$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +strict +delete
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +strict +delete
$x->[0] = 1 # exists $x->[0] # '', 1, [ 1 ] # +strict +store
$x->[0] = 1 # exists $x->[1] # '', '', [ 1 ] # +strict +store

$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +fetch
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +fetch
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ], undef, [ ] ] # +fetch
$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +exists
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +exists
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ] ] # +exists
$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +delete
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +delete
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ], undef, [ ] ] # +delete
$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +store
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +store
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ], undef, [ ] ] # +store

$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +fetch
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +strict +fetch
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ], undef, [ ] ] # +strict +fetch
$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +exists
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +strict +exists
$x->[0]->[1] = 1 # exists $x->[2]->[3] # qr/^Reference vivification forbidden/, undef, [ [ undef, 1 ] ] # +strict +exists
$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +delete
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +strict +delete
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ], undef, [ ] ] # +strict +delete
$x->[0]->[1] = 1 # exists $x->[0]->[1] # '', 1, [ [ undef, 1 ] ] # +strict +store
$x->[0]->[1] = 1 # exists $x->[0]->[3] # '', '', [ [ undef, 1 ] ] # +strict +store
$x->[0]->[1] = 1 # exists $x->[2]->[3] # '', '', [ [ undef, 1 ], undef, [ ] ] # +strict +store

--- delete ---

$x # delete $x->[0] # '', undef, [ ]
$x # delete $x->[0] # '', undef, undef #
$x # delete $x->[0] # '', undef, [ ] # +fetch
$x # delete $x->[0] # '', undef, [ ] # +exists
$x # delete $x->[0] # '', undef, undef # +delete
$x # delete $x->[0] # '', undef, [ ] # +store

$x # delete $x->[0] # '', undef, [ ] # +strict +fetch
$x # delete $x->[0] # '', undef, [ ] # +strict +exists
$x # delete $x->[0] # qr/^Reference vivification forbidden/, undef, undef # +strict +delete
$x # delete $x->[0] # '', undef, [ ] # +strict +store

$x # delete $x->[0]->[1] # '', undef, [ [ ] ]
$x # delete $x->[0]->[1] # '', undef, undef #
$x # delete $x->[0]->[1] # '', undef, [ [ ] ] # +fetch
$x # delete $x->[0]->[1] # '', undef, [ [ ] ] # +exists
$x # delete $x->[0]->[1] # '', undef, undef # +delete
$x # delete $x->[0]->[1] # '', undef, [ [ ] ] # +store

$x # delete $x->[0]->[1] # '', undef, [ [ ] ] # +strict +fetch
$x # delete $x->[0]->[1] # '', undef, [ [ ] ] # +strict +exists
$x # delete $x->[0]->[1] # qr/^Reference vivification forbidden/, undef, undef # +strict +delete
$x # delete $x->[0]->[1] # '', undef, [ [ ] ] # +strict +store

$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +fetch
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +fetch
$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +exists
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +exists
$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +delete
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +delete
$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +store
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +store

$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +strict +fetch
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +strict +fetch
$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +strict +exists
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +strict +exists
$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +strict +delete
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +strict +delete
$x->[0] = 1 # delete $x->[0] # '', 1, [ ] # +strict +store
$x->[0] = 1 # delete $x->[1] # '', undef, [ 1 ] # +strict +store

$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +fetch
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ]# +fetch
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +fetch
$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +exists
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ]# +exists
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +exists
$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +delete
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ]# +delete
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ] ]# +delete
$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +store
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ]# +store
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ] # +store

$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +strict +fetch
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +fetch
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ]# +strict +fetch
$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +strict +exists
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +exists
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ]# +strict +exists
$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +strict +delete
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +delete
$x->[0]->[1] = 1 # delete $x->[2]->[3] # qr/^Reference vivification forbidden/, undef, [ [ undef, 1 ] ] # +strict +delete
$x->[0]->[1] = 1 # delete $x->[0]->[1] # '', 1, [ [ ] ] # +strict +store
$x->[0]->[1] = 1 # delete $x->[0]->[3] # '', undef, [ [ undef, 1 ] ] # +strict +store
$x->[0]->[1] = 1 # delete $x->[2]->[3] # '', undef, [ [ undef, 1 ], undef, [ ] ]# +strict +store

--- store ---

$x # $x->[0] = 1 # '', 1, [ 1 ]
$x # $x->[0] = 1 # '', 1, [ 1 ] #
$x # $x->[0] = 1 # '', 1, [ 1 ] # +fetch
$x # $x->[0] = 1 # '', 1, [ 1 ] # +exists
$x # $x->[0] = 1 # '', 1, [ 1 ] # +delete
$x # $x->[0] = 1 # qr/^Can't vivify reference/, undef, undef # +store

$x # $x->[0] = 1 # '', 1, [ 1 ] # +strict +fetch
$x # $x->[0] = 1 # '', 1, [ 1 ] # +strict +exists
$x # $x->[0] = 1 # '', 1, [ 1 ] # +strict +delete
$x # $x->[0] = 1 # qr/^Reference vivification forbidden/, undef, undef # +strict +store

$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ]
$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] #
$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] # +fetch
$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] # +exists
$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] # +delete
$x # $x->[0]->[1] = 1 # qr/^Can't vivify reference/, undef, undef # +store

$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] # +strict +fetch
$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] # +strict +exists
$x # $x->[0]->[1] = 1 # '', 1, [ [ undef, 1 ] ] # +strict +delete
$x # $x->[0]->[1] = 1 # qr/^Reference vivification forbidden/, undef, undef # +strict +store

$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +fetch
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +fetch
$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +exists
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +exists
$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +delete
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +delete
$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +store
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +store

$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +strict +fetch
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +strict +fetch
$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +strict +exists
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +strict +exists
$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +strict +delete
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +strict +delete
$x->[0] = 1 # $x->[0] = 2 # '', 2, [ 2 ] # +strict +store
$x->[0] = 1 # $x->[1] = 2 # '', 2, [ 1, 2 ] # +strict +store

$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +fetch
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +fetch
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # '', 2, [ [ undef, 1 ], undef, [ undef, undef, undef, 2 ] ] # +fetch
$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +exists
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +exists
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # '', 2, [ [ undef, 1 ], undef, [ undef, undef, undef, 2 ] ] # +exists
$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +delete
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +delete
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # '', 2, [ [ undef, 1 ], undef, [ undef, undef, undef, 2 ] ] # +delete
$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +store
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +store
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # qr/^Can't vivify reference/, undef, [ [ undef, 1 ] ] # +store

$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +strict +fetch
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +strict +fetch
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # '', 2, [ [ undef, 1 ], undef, [ undef, undef, undef, 2 ] ] # +strict +fetch
$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +strict +exists
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +strict +exists
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # '', 2, [ [ undef, 1 ], undef, [ undef, undef, undef, 2 ] ] # +strict +exists
$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +strict +delete
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +strict +delete
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # '', 2, [ [ undef, 1 ], undef, [ undef, undef, undef, 2 ] ] # +strict +delete
$x->[0]->[1] = 1 # $x->[0]->[1] = 2 # '', 2, [ [ undef, 2 ] ] # +strict +store
$x->[0]->[1] = 1 # $x->[0]->[3] = 2 # '', 2, [ [ undef, 1, undef, 2 ] ] # +strict +store
$x->[0]->[1] = 1 # $x->[2]->[3] = 2 # qr/^Reference vivification forbidden/, undef, [ [ undef, 1 ] ] # +strict +store
