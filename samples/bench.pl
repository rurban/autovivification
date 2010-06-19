#!perl

use strict;
use warnings;

use Benchmark qw/cmpthese/;

my $count = -1;

{
 my %h = (
  a => 1,
 );

 cmpthese $count, {
  fetch_hash_existing_av   => sub { $h{a} },
  fetch_hash_existing_noav => sub { no autovivification; $h{a} },
 };
}

{
 my %h = ();

 cmpthese $count, {
  fetch_hash_nonexisting_av   => sub { $h{a} },
  fetch_hash_nonexisting_noav => sub { no autovivification; $h{a} },
 };
}

{
 my $x = {
  a => 1,
 };

 cmpthese $count, {
  fetch_hashref_existing_av   => sub { $x->{a} },
  fetch_hashref_existing_noav => sub { no autovivification; $x->{a} },
 };
}

{
 my $x = { };

 cmpthese $count, {
  fetch_hashref_nonexisting_av   => sub { $x->{a} },
  fetch_hashref_nonexisting_noav => sub { no autovivification; $x->{a} },
 };
}
