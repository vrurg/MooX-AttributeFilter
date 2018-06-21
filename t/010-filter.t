use 5.010000;
use strict;
use warnings;
use Test2::V0;
use Test2::Tools::Spec ':ALL';
use __MAF::Test;

describe filtering => sub {

    my $generator;
    my $filterCase;

    case Class => sub {
        $generator  = \&_class_generator;
        $filterCase = 'Class';
    };
    case Role => sub {
        $generator  = \&_role_generator;
        $filterCase = 'Role';
    };

    describe Basic => sub {
        my ( $filterOpt, $filterSub );

        # filter => sub {},
        case Anonymous => sub {
            $filterOpt = q<sub {
        my $this = shift;
        return "basicFlt($_[0])";
    }>;
            $filterSub = '';
        };

        # filter => 1,
        case Default => sub {
            $filterOpt = '1';
            $filterSub = q<sub _filter_attr {
    my $this = shift;
    return "basicFlt($_[0])";
}>;
        };

        # filter => 'namedFilter',
        case Named => sub {
            $filterOpt = q<'namedFilter'>;
            $filterSub = q<sub namedFilter {
    my $this = shift;
    return "basicFlt($_[0])";
}>;
        };

        describe RWMode => sub {
            my $rwMode;

            case RW  => sub { $rwMode = 'rw' };
            case RWP => sub { $rwMode = 'rwp' };
            case RO  => sub { $rwMode = 'ro' };

            tests Constructor => sub {
                my $class = $generator->(
                    body => <<CODE,
use MooX::AttributeFilter;

has attr => (
    is => '${rwMode}',
    filter => $filterOpt,
);

has noFilter => (
    is => '${rwMode}',
);

$filterSub
CODE
                );

                my $val   = _randomName;
                my $nfVal = "nofilter_" . $val;
                my $o     = $class->new( attr => $val, noFilter => $nfVal );
                is( $o->attr,     "basicFlt($val)", "attribute filtered" );
                is( $o->noFilter, $nfVal,           "unfiltered attribute ok" );
            };

            tests Writer => sub {
                my $class = $generator->(
                    body => <<CODE,
use MooX::AttributeFilter;

has attr => (
    is => '${rwMode}',
    filter => $filterOpt,
    writer => 'setAttr',
);

has noFilter => (
    is => '${rwMode}',
    writer => 'setNoFilter',
);

$filterSub
CODE
                );

                my $val   = _randomName;
                my $nfVal = "nofilter_" . $val;
                my $o     = $class->new;
                $o->setAttr($val);
                $o->setNoFilter($nfVal);
                is( $o->attr,     "basicFlt($val)", "attribute filtered" );
                is( $o->noFilter, $nfVal,           "unfiltered attribute ok" );
            };
        };
    };

    my $oldValueBody = <<'CODE';
use MooX::AttributeFilter;

has attr => (
    is     => 'rw',
    filter => sub {
        my $this = shift;
        if ( @_ == 1 ) {
            $this->oldValue("construction stage");
        }
        else {
            $this->oldValue( $_[1] );
        }
        return $_[0];
    },
);

has oldValue => ( is => 'rw', );
CODE
    tests OldValue => sub {
        my $class = $generator->( body => $oldValueBody, );
        my $o = $class->new( attr => 'init' );
        like( $o->oldValue, "construction stage", "construction stage" );
        $o->attr("postinit");
        like( $o->oldValue, "init", "old value preserved" );

        $o = $class->new;
        $o->attr("first");
        ok( !defined $o->oldValue, "old value undefined for the first write" );
    };

    tests Laziness => sub {
        my $class = $generator->(
            body => <<'CODE',
use MooX::AttributeFilter;

# To record number of arguments of filter sub
has args => (
    is => 'rw',
);

has lz_default => (
    is      => 'rw',
    lazy    => 1,
    default => 'defVal',
    filter  => 'lzFilter',
);

has lz_builder => (
    is      => 'rw',
    lazy    => 1,
    builder => 'initLzBuilder',
    filter  => 'lzFilter',
);

sub lzFilter {
    my $this = shift;
    $this->args(scalar @_);
    return "lazy_or_not($_[0])";
}

sub initLzBuilder {
    return "builtVal";
}
CODE
        );
        my $o = $class->new;
        like( $o->lz_default, "lazy_or_not(defVal)", "lazy init with default" );
        is( $o->args, 1, "lazy init filter has 1 arg" );
        $o->lz_default("3.1415926");
        like( $o->lz_default, "lazy_or_not(3.1415926)",
            "lazy attribute set ok" );
        is( $o->args, 2, "lazy argument set filter has 2 args" );
        like( $o->lz_builder, "lazy_or_not(builtVal)",
            "lazy init with builder" );
    };

    tests Triggering => sub {
        my $class = $generator->(
            body => <<'CODE',
use MooX::AttributeFilter;

has tattr => (
    is      => 'rw',
    trigger => 1,
    filter  => 1,
);

has trig_arg => ( is => 'rw' );

sub _trigger_tattr {
    my $this = shift;
    $this->trig_arg( $_[0] );
}

sub _filter_tattr {
    my $this = shift;
    return "_filter_tattr($_[0])";
}
CODE
        );

        my $o = $class->new( tattr => "init" );
        like( $o->trig_arg, "_filter_tattr(init)",
            "triggered from constructor" );
        $o->tattr("set");
        like( $o->trig_arg, "_filter_tattr(set)", "triggered from write" );
    };

    tests Coercing => sub {
        my $class = $generator->(
            body => <<'CODE',
use MooX::AttributeFilter;

has cattr => (
    is     => 'rw',
    coerce => sub { $_[0] + 1 },
    filter => sub {
        my $this = shift;
        return -$_[0];
    },
);
CODE
        );

        my $o = $class->new;
        $o->cattr(3.1415926);
        is( $o->cattr, -2.1415926, "coerce applied" );
    };

    tests 'ChildNoFilter' => sub {
        my $oldValClass =
          $generator->( name => 'OldValue', body => $oldValueBody, );
        my $class = $generator->( 'extends' => 'OldValue', );

        my $o = $class->new( attr => "construction" );
        $o->attr("set");
        like( $o->attr,     "set",          "attribute set" );
        like( $o->oldValue, "construction", "old value preserved" );
    };

    my $noFilterBody = <<'CODE';
has attr => (
    is     => 'rw',
    filter => sub {
        my $this = shift;
        return "filtered($_[0])";
    },
);

has no_flt => ( is => 'rw', );
CODE
    tests NoFilter => sub {
        my $class = $generator->( body => $noFilterBody, );

        # Check if accidental filter applying happens.

        my $o = $class->new;
        $o->attr("value");
        like( $o->attr, "value",
            "we don't install filter if not requested by class" );
    };

    tests ChildOverride => sub {
      SKIP: {
            skip 'Attribute modification doesn\'t play well for roles'
              if $filterCase eq 'Role';

            my $noFilterClass =
              $generator->( name => 'NoFilter', body => $noFilterBody );
            my $class = $generator->(
                'extends' => 'NoFilter',
                body      => <<'CODE',
use MooX::AttributeFilter;

has '+attr' => ();

has '+no_flt' => (
    filter => sub {
        my $this = shift;

        return "no_flt($_[0])";
    },
);

has myAttr => (
    is     => 'rw',
    filter => sub {
        my $this = shift;
        return "myAttr($_[0])";
    },
);
CODE
            );

            my $o = $class->new;
            $o->attr("abc");

            # This is unintended side effect. Not sure if it worth fixing...
            like( $o->attr, "filtered(abc)", "O'RLY?" );
            $o->no_flt("123");
            like( $o->no_flt, "no_flt(123)", "unfiltered attribute upgrade" );
            $o->myAttr("3.1415926");
            like( $o->myAttr, "myAttr(3.1415926)", "own filtered attribute" );
        }
    };

    tests Complex => sub {
        my $class = $generator->(
            body => <<'CODE',
use MooX::AttributeFilter;

has a1 => (
    is      => 'rw',
    default => 10,
);

has a2 => (
    is      => 'rw',
    default => 2,
);

has af => (
    is     => 'rw',
    filter => 'filterAF',
);

has progressive => (
    is     => 'rw',
    filter => sub {
        my $this = shift;
        return $_[0] + ( $_[1] || 0 );
    },
);

sub filterAF {
    my $this = shift;
    return $_[0] * $this->a1 + $this->a2;
}
CODE
        );

        my $o = $class->new;
        $o->af(1);
        is( $o->af, 12, "other attributes involved" );

        my @prog = ( 1, 1, 1, 2, 1, 3, 4, 7, 1, 8 );
        use List::Util qw<pairs>;

        my $step = 0;
        foreach my $pair ( pairs @prog ) {
            $o->progressive( $pair->[0] );
            is( $o->progressive, $pair->[1], "progressive step #" . ++$step );
        }
    };

    tests Typed => sub {
        my $class = $generator->(
            body => <<'CODE',
use MooX::AttributeFilter;
use Scalar::Util qw<looks_like_number>;

has typed => (
    is  => 'rw',
    isa => sub {
        die "Bad typed value '$_[0]'" unless looks_like_number( $_[0] );
    },
    filter => sub {
        my $this = shift;
        my $val  = $_[0];
        $val =~ s/^prefix//;
        return $val;
    }
);

CODE
        );

        my $o = $class->new;
        try_ok {
            $o->typed(123);
            is( $o->typed, 123, "simple num" );
            $o->typed("prefix10");
            is( $o->typed, 10, "prefix removed" );
        };
        like(
            dies { $o->typed("bad!"); },
            qr/Bad typed value 'bad!'/,
            "bad value handled"
        );
    };

    tests DefaultVal => sub {
        my $class = $generator->(
            body => <<'CODE',
use MooX::AttributeFilter;

has defAttr => (
    is => 'rw',
    default => 3.1415926,
    filter => sub {
        my $this = shift;
        return "filtered($_[0])";
    },
);
CODE
        );

        my $o = $class->new;
        is( $o->defAttr, "filtered(3.1415926)",
            "default passed through filter" );
    };

    describe CallOrder => sub {
        my $filterOpts;
        my $callOrderCase;

        eval { require Types::Standard; };
        my $noTypes = $@ ? "Types::Standard required for this test" : !!0;

        case no_filter => sub {
            $filterOpts = {};
        };

        case filter_bool => sub {
            $filterOpts = {
                body_opt => 'filter => 1',
                body =>
'sub _filter_attr {push @callOrder, "filter";return "filtered($_[1])"}',
            };
        };

        case filter_named => sub {
            $filterOpts = {
                body_opt => "filter => 'filterAttr'",
                body =>
'sub filterAttr {push @callOrder, "filter"; return "filtered($_[1])";}',
            };
        };

        describe MooOptions => sub {
            my $mooOpts;

            case isa_simple => sub {
                use Carp;
                $mooOpts => {
                    body_opt  => 'isa => StrMatch[qr/^filtered\(.*\)$/]',
                    body_head => 'use Types::Standard qw<StrMatch>;',
                    skip      => $noTypes,
                };
            };

            case isa_inline => sub {
                $mooOpts => {
                    body_opt =>
                      'isa => sub {push @callOrder, "isa"; return 1;}',
                    option => 'isa',
                };
            };

            case is_coderef => sub {
                $mooOpts => {
                    body_opt => 'isa => \&isaSub',
                    body   => 'sub isaSub {push @callOrder, "isa"; return 1;}',
                    option => 'isa',
                };
            };

            case types_coerce => sub {
                $mooOpts => {
                    body_opt =>
q|    isa => (StrMatch[qr/^filtered\(.*\)/])->where(sub{push @callOrder, "coerce"; $_[0]}),
    coerce => 1|,
                    body_head => 'use Types::Standard qw<StrMatch Str>;',
                    skip      => $noTypes,
                    option    => 'isa',
                };
            };

            case coerce_inline => sub {
                $mooOpts => {
                    body_opt =>
                      'coerce => sub { push @callOrder, "coerce"; $_[0]}',
                    option => 'coerce',
                };
            };

            tests call_order => sub {
                skip_all $mooOpts->{skip} if $mooOpts->{skip};

                my $testClassBody = q|
use MooX::AttributeFilter;
|
                  . ( $mooOpts->{body_head}    || '' ) . "\n"
                  . ( $filterOpts->{body_head} || '' ) . q|
our @callOrder;

has attr => (
    is => 'rw',
|
                  . ( $mooOpts->{body_opt}    || '' ) . ",\n"
                  . ( $filterOpts->{body_opt} || '' ) . q|,
);
|
                  . ( $mooOpts->{body}    || '' ) . "\n"
                  . ( $filterOpts->{body} || '' ) . q|
          
sub resetOrder {
    @callOrder = ();
}

sub getOrder {
    return \@callOrder;
}
1;|;
                my $testClass =
                  $generator->( body => $testClassBody, name => '' );
                if ( $filterOpts->{body_opt} ) {
                    subtest with_filter => sub {
                        $testClass->resetOrder;
                        my $obj;
                        try_ok {
                            $obj = $testClass->new( attr => "3.1415926" );
                        }
                        "new finishes normally";
                        is( $obj->attr, "filtered(3.1415926)",
                            "value passed the filter with constructor" );
                        is( $testClass->getOrder->[0],
                            'filter',
                            "filter was called first with constructor" );

                        $testClass->resetOrder;
                        try_ok {
                            $obj->attr("12345");
                        }
                        "attribute setter finishes normally";
                        is( $obj->attr, "filtered(12345)",
                            "value passed the filter with setter" );
                        is( $testClass->getOrder->[0],
                            'filter', "filter was called first with setter" );
                        if ( $mooOpts->{option} ) {
                            is( $testClass->getOrder->[1],
                                $mooOpts->{option},
                                $mooOpts->{option} . " was called second" );
                        }
                    };
                }
                else {
                    subtest without_filter => sub {
                        my $obj = $testClass->new( attr => "3.1415926" );
                        is( $obj->attr, "3.1415926", "not filtered" );
                    };
                }
            };
        };
    };
};

done_testing;
