package autovivification::TestCases;

use strict;
use warnings;

use Test::More;

sub import {
 no strict 'refs';
 *{caller().'::testcase_ok'} = \&testcase_ok;
}

sub in_strict { (caller 0)[8] & (eval { strict::bits(@_) } || 0) };

sub generate {
 my ($var, $init, $code, $exp, $use, $opts, $global) = @_;
 my $decl = $global ? "our $var; local $var;" : "my $var;";
 my $test = $var =~ /^[@%]/ ? "\\$var" : $var;
 my $desc = join('; ', map { my $x = $_; $x=~ s,;\s*$,,; $x }
                                   grep /\S/, $decl, $init, $code) . " <$opts>";
 return <<TESTCASE, $desc;
$decl
$init
my \$strict = autovivification::TestCases::in_strict('refs');
my \@exp = ($exp);
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
  [ $var, $init,               $code, $exp, $use, $opts, 0 ],
  [ $var, "use strict; $init", $code, $exp, $use, $opts, 1 ],
  [ $var, "no strict;  $init", $code, $exp, $use, $opts, 1 ],
 );
 my @extra;
 for (@testcases) {
  my $var = $_->[0];
  if ($var =~ /\$/) {
   my @new = @$_;
   $new[0] =~ s/^\$/$sigil/;
   for ($new[1], $new[2]) {
    s/\Q$sigil$var\E/$new[0]/g;
    s/\Q$var\E\->/$var/g;
   }
   my $simple      = $new[2] !~ /->/;
   my $plain_deref = $new[2] =~ /\Q$new[0]\E/;
   my $empty  = { '@' => '[ ]', '%' => '{ }' }->{$sigil};
   if (($simple
        and (   $new[3] =~ m!qr/\^Reference vivification forbidden.*?/!
             or $new[3] =~ m!qr/\^Can't vivify reference.*?/!))
    or ($plain_deref
        and $new[3] =~ m!qr/\^Can't use an undefined value as a.*?/!)) {
    $new[1] = '';
    $new[2] = 1;
    $new[3] = "'', 1, $empty";
   }
   $new[3] =~ s/,\s*undef\s*$/, $empty/;
   push @extra, \@new;
  }
 }
 push @testcases, @extra;
 for (@testcases) {
  my ($testcase, $desc) = generate(@$_);
  eval $testcase;
  diag "== This testcase failed to compile ==\n$testcase\n## Reason: $@" if $@;
 }
}

1;
