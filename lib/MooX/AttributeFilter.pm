#

package MooX::AttributeFilter;
use strictures 1;

our $VERSION = '0.001000';

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
