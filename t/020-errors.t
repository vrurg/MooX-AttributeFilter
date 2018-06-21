#
use strict;
use warnings;
use Test2::V0;

eval {
    package BadRef;
    use Moo;
    use MooX::AttributeFilter;

    has attr => (
        is     => 'rw',
        filter => {},
    );
    1;
};
like(
    $@,
    qr/Attribute 'attr' filter option has invalid value/,
    "filter's incorrect ref"
);

eval {
    package BadMethod;
    use Moo;
    use MooX::AttributeFilter;

    has attr => (
        is     => 'rw',
        filter => 'noFilter',
    );
    1;
};
like(
    $@,
    qr/No filter method 'noFilter' defined for BadMethod attribute 'attr'/,
    "no filter method"
);

done_testing;
