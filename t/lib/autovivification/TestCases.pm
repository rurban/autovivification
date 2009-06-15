package autovivification::TestCases;

use strict;
use warnings;

use Test::More;

sub import {
 no strict 'refs';
 *{caller().'::testcase_ok'} = \&testcase_ok;
}

sub source {
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

sub testcase_ok {
 local $_  = shift;
 my $sigil = shift;
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
   $new[0] =~ s/^$/$sigil/;
   $new[1] =~ s/$var\->/$var/g;
   $new[2] =~ s/$var\->/$var/g;
   push @extra, \@new;
  }
 }
 push @testcases, @extra;
 for (@testcases) {
  my $testcase = source(@$_);
  my ($var, $init, $code) = @$_;
  my $desc = do { (my $x = "$var | $init") =~ s,;\s+$,,; $x } . " | $code | $opts";
  eval $testcase;
  diag "== This testcase failed to compile ==\n$testcase\n## Reason: $@" if $@;
 }
}

1;
