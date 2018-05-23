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

has attr2 => (
    is     => 'rw',
    filter => 'filter2',
);

sub _filter_attr {
    my $this = shift;
    return "filtered($_[0])";
}

sub filter2 {
    my $this = shift;
    return "second($_[0])";
}

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
        "Cannot test without required Moose and MooseX::AttributeFilter modules"
    ) if $skipTest;
}

eval q{
    package MooseClass;
    use Moose;
    extends qw<MooClass>;
};

use Test::Moose;

with_immutable {
    my $obj = MooseClass->new;
    $obj->attr("a value");
    is( $obj->attr, "filtered(a value)", "_filter_attr for attr" );
    $obj->attr2("3.1415926");
    is( $obj->attr2, "second(3.1415926)", "filter2 for attr2" );
}
qw<MooseClass>;

done_testing;
