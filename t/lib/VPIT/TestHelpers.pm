package VPIT::TestHelpers;

use strict;
use warnings;

my %exports = (
 load_or_skip => \&load_or_skip,
 skip_all     => \&skip_all,
);

sub import {
 my $pkg = caller;
 while (my ($name, $code) = each %exports) {
  no strict 'refs';
  *{$pkg.'::'.$name} = $code;
 }
}

my $test_sub = sub {
 my $sub = shift;
 my $stash;
 if ($INC{'Test/Leaner.pm'}) {
  $stash = \%Test::Leaner::;
 } else {
  require Test::More;
  $stash = \%Test::More::;
 }
 my $glob = $stash->{$sub};
 return $glob ? *$glob{CODE} : undef;
};

sub skip_all { $test_sub->('plan')->(skip_all => $_[0]) }

sub diag {
 my $diag = $test_sub->('diag');
 $diag->($_) for @_;
}

our $TODO;
local $TODO;

sub load_or_skip {
 my ($pkg, $ver, $imports, $desc) = @_;
 my $spec = $ver && $ver !~ /^[0._]*$/ ? "$pkg $ver" : $pkg;
 local $@;
 if (eval "use $spec (); 1") {
  $ver = do { no strict 'refs'; ${"${pkg}::VERSION"} };
  $ver = 'undef' unless defined $ver;
  if ($imports) {
   my @imports = @$imports;
   my $caller  = (caller 0)[0];
   local $@;
   my $res = eval <<"IMPORTER";
package
        $caller;
BEGIN { \$pkg->import(\@imports) }
1;
IMPORTER
   skip_all "Could not import '@imports' from $pkg $ver: $@" unless $res;
  }
  diag "Using $pkg $ver";
 } else {
  (my $file = "$pkg.pm") =~ s{::}{/}g;
  delete $INC{$file};
  skip_all "$spec $desc";
 }
}

package VPIT::TestHelpers::Guard;

sub new {
 my ($class, $code) = @_;

 bless { code => $code }, $class;
}

sub DESTROY { $_[0]->{code}->() }

1;
