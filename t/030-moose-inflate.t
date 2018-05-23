#
use strict;
use warnings;
use Test2::V0;

package MooClass;

use Moo;
use MooX::AttributeFilter;

has attr => (
    is     => 'rw',
    filter => 1,
);

sub _filter_attr {
    my $this = shift;
    return "filtered($_[0])";
}

package MooseClass;
use Moose;
extends qw<MooClass>;

package main;

BEGIN {
my $skipTest = 1;
eval {
    use Module::Load;
    load Moose;
    load MooseX::AttributeFilter;
    $skipTest = 0;
};

skip_all(
    "Cannot test without required Moose and MooseX::AttributeFilter modules")
  if $skipTest;
}
  
use Test::Moose;
  
with_immutable {
    my $obj = MooseClass->new;
    $obj->attr("a value");
    is( $obj->attr, "filtered(a value)", "filter was called" );
} qw<MooseClass>;

done_testing;
