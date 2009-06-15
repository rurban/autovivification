#!perl

use strict;
use warnings;

use Fatal qw/open/;
use Text::Balanced qw/extract_bracketed/;

open my $hash_t,  '<', 't/20-hash.t';
open my $array_t, '>', 't/21-array.t';

sub num { ord($_[0]) - ord('a') }

sub hash2array {
 my ($h) = @_;
 return $h unless $h and ref $h eq 'HASH';
 my @array;
 for (keys %$h) {
  $array[num($_)] = hash2array($h->{$_});
 }
 return \@array;
}

sub dump_array {
 my ($a) = @_;
 return 'undef' unless defined $a;
 return $a      unless ref $a;
 die "Invalid argument" unless ref $a eq 'ARRAY';
 return '[ ' . join(', ', map dump_array($_), @$a) . ' ]';
}

sub extract ($) { extract_bracketed $_[0], '{',  qr/.*?(?<!\\)(?:\\\\)*(?={)/ }

my $in_data;
while (<$hash_t>) {
 if (/^__DATA__$/) {
  $in_data = 1;
  print $array_t $_;
 } elsif (!$in_data) {
  s{'%'}{'\@'};
  print $array_t $_;
 } else {
  s!->{([a-z])}!'->[' . num($1) . ']'!eg;
  my $buf;
  my $suffix = $_;
  my ($bracket, $prefix);
  while (do { ($bracket, $suffix, $prefix) = extract($suffix); $bracket }) {
   $buf .= $prefix . dump_array(hash2array(eval $bracket));
  }
  $buf .= $suffix;
  $buf =~ s/\s+/ /g;
  $buf =~ s/\s+$//;
  print $array_t "$buf\n";
 }
}
