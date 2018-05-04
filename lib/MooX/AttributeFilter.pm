#
# ABSTRACT: Implements 'filter' option for Moo-class attributes
=head1 SYNOPSIS

    package My::Class {
        use Moo;
        use MooX::AttributeFilter;
        
        has field => (
            is     => 'rw',
            filter => 'filterField',
        );
        
        has lazyField => (
            is      => 'rw',
            lazy    => 1,
            builder => sub { [1, 2, 3 ] },
            filter  => 1,
        );
        
        has incremental => (
            is => 'rw',
            filter => sub {
                my $this = shift;
                my ($val, $oldVal) = @_;
                if ( @_ > 1 && defined $oldVal ) {
                    die "incremental attribute value may only increase"
                        unless $val > $oldVal;
                }
                return $_[0];
            }
        );
        
        sub filterField {
            my $this = shift;
            return "filtered($_[0])";
        }
        
        sub _filter_lazyField {
            my $this = shift;
            my @a = @{$_[0]};
            push @a, -1;
            return \@a;
        }
    }
    
    my $obj = My::Class->new( field => "initial" );
    ($obj->field eq "filtered(initial)")  # True!
    $obj->lazyField;                      # [ 1, 2, 3, -1 ]
    $obj->field( "value" );               # "filtered(value)"
    $obj->incremental( -1 );              # -1
    $obj->incremental( 10 );              # 10
    $obj->incremental( 9 );               # dies...
    
    $obj = My::Class->new( incremental => 1 ); # incremental is set to 1
    $obj->incremental( 0 );                    # dies too.
    
=head1 DESCRIPTION

The idea behind this extension is to overcome the biggest deficiency of
coercion: its ignorance about the object it is acting for. Triggers are executed
as methods but they don't receive the previous value and they're called after
attribute is set.

A filter is a method which is called right before attribute value is about to be
set and receives 1 or two arguments of which the first one is the new attribute
value; the second one is the old value. Number of arguments passed depends on
when the filter get called: on the construction stage it is one, and it is two
when set manually. B<Note> that in the latter case if it's the first time the
attribute is set the old value would be undefined.

It is also worth mentioning that filter is called always when attribute is
set, including initialization from constructor arguments or lazy builders. See
the SYNOPSIS. In both cases filter gets called with a single argument.

I.e.:

    package LazyOne {
        use Moo;
        use MooX::AttributeFilter;
        
        has lazyField => (
            is => 'rw',
            lazy => 1,
            default => "value",
            filter => sub {
                my $this = shift;
                say "Arguments: ", scalar(@_);
                return $_[0];
            },
        );
    }
    
    my $obj = LazyOne->new;
    $obj->lazyField;        # Arguments: 1
    $obj->lazyField("foo"); # Arguments: 2
    
    $obj = LazyOne->new( lazyField => "bar" );  # Arguments: 1
    $obj->lazyField( "foobar" );                # Arguments: 2
    
A filter method must always return a (possibly changed) value to be stored in
the attribute.

Filter called I<before> anything else on the attribute. Its return value is then
subject for passing through C<isa> and C<coerce>.

=head2 Use cases

Filters are of the most use when attribute value (or allowed values) depends on
other attributes of its object. The dependency could be hard (or C<isa>-like) –
i.e. when an exception must be thrown if value doesn't pass validation. Or it
could be soft when by storing a vlue code I<suggest> what it would like to see
in the attribute but the resulting value might be changed depending on the
current environment. For example:

    package ChDir {
        use File::Spec;
        use Moo;
        extends qw<Project::BaseClass>;
        use MooX::AttributeFilter;
        
        has curDir => (
            is => 'rw',
            filter => 'chDir',
        );
        
        sub chDir {
            my $this = shift;
            my ( $subdir ) = @_;
            
            return File::Spec->catdir(
                $this->testMode ? $this->baseTestDir : $this->baseDir,
                $subdir
            );
        }
    }
    
=head1 CAVEATS

* This module doesn't inflate into Moose.

* The code relies on very low-level functionality of Method::Generate family
  of modules. For this reason it may become incompatible with a future versions
  of the modules.

=head1 ACKNOWLEDGEMENT

This module is a result of rejection to include filtering functionality into
the Moo core. Since the reasoning behind the rejection was really convincing
but the functionality is badly wanted I had no choices left... So, my great
thanks to Graham Knopp <haarg@haarg.org> for his advises, sample code, and
Moo itself, of course!

=cut

package MooX::AttributeFilter;
use strictures 1;

our $VERSION = '0.001001';

use Carp;
use Scalar::Util qw<looks_like_number>;
use Class::Method::Modifiers qw(install_modifier);
use Sub::Quote qw<quotify>;
use Data::Dumper;
require Method::Generate::Accessor;

my %filterClasses;

install_modifier "Method::Generate::Accessor", 'around',
  '_generate_core_set', sub {
    my $orig = shift;
    my $this = shift;
    my ( $me, $name, $spec, $value ) = @_;

    my $filterVal = $value;

    #say STDERR "Generating core set for $me,$name,$spec,$value";
    #say STDERR Dumper( $this->{captures} );
    if ( $spec->{filter} && $spec->{filter_sub} && !$spec->{".filter_no_core"} )
    {

        #say STDERR "FILTER IS:", $spec->{filter_sub}, ", value:", $value;
        $this->{captures}{ '$filter_for_' . $name } = \$spec->{filter_sub};
        $filterVal =
          $this->_generate_call_code( $name, 'filter', "${me}, ${value}",
            $spec->{filter_sub} );
    }

    return $orig->( $this, $me, $name, $spec, $filterVal );
  };

install_modifier "Method::Generate::Accessor", 'around', 'is_simple_set', sub {
    my $orig = shift;
    my $this = shift;
    my ( $name, $spec ) = @_;
    return $orig->( $this, @_ ) && !( $spec->{filter} && $spec->{filter_sub} );
};

install_modifier "Method::Generate::Accessor", 'around', '_generate_set', sub {
    my $orig = shift;
    my $this = shift;
    my ( $name, $spec ) = @_;
    local $spec->{".filter_no_core"} = 1;

    #say STDERR "* Generating set: (", join( ",", @_ ), ")";
    my $rc = $orig->( $this, @_ );

    #say STDERR "* Generated set code: ", $rc;

    return $rc unless $spec->{filter} && $spec->{filter_sub};

    my $capName = '$filter_for_' . $name;

    # Call to the filter was generated already.
    unless ( $this->{captures}{$capName} ) {

    # Work around Method::Generate::Accessor limitation: it predefines source
    # as being $_[1] only and not acceping any argument to define it externally.
    # For this purpose the only solution we have is to wrap it into a sub and
    # pass the filter as sub's argument.

        my $name_str = quotify $name;
        $rc = "sub { $rc }->( \$_[0], "
          . $this->_generate_call_code( $name, 'filter',
            "\$_[0], \$_[1], \$_[0]->{${name_str}}",
            $spec->{filter_sub} )
          . " )";
    }

    #say STDERR "* Generated final set code: ", $rc;

    return $rc;
};

install_modifier "Method::Generate::Accessor", 'around', 'generate_method',
  sub {
    my $orig = shift;
    my $this = shift;
    my ( $into, $name, $spec, $quote_opts ) = @_;

    if ( $filterClasses{$into} && $spec->{filter} ) {

        #say STDERR "--- Installing filter into ${into}::${name}";

        croak "Incompatibe 'is' option '$spec->{is}': can't install filter"
          unless $spec->{is} =~ /^rwp?$/n;

        my $filterSub;
        if ( $spec->{filter} eq 1 ) {
            $filterSub = "_filter_${name}";
        }
        else {
            $filterSub = $spec->{filter};
        }
        $spec->{filter} = 1;

        croak "Attribute '$name' filter option has invalid value"
          if ref($filterSub) && ref($filterSub) ne 'CODE';

        my $filterCode = ref($filterSub) ? $filterSub : $into->can($filterSub);

        croak
          "No filter method '$filterSub' defined for $into attribute '$name'"
          unless $filterCode;

        $spec->{filter_sub} = $filterCode;
    }

    return $orig->( $this, @_ );
  };

sub import {
    my ($class) = @_;
    my $target = caller;

    $filterClasses{$target} = 1;
}

1;
