package __MAF::Test;

use Exporter;
our @ISA = qw<Exporter>;

our @EXPORT = qw<_class_generator _role_generator _randomName>;

sub _randomName {
    my $chars = [ 'A' .. 'Z', 'a' .. 'z', '0' .. '9' ];
    my $name = '';
    $name .= $chars->[ rand( scalar @$chars ) ] for 1 .. 6;
    return "Tst_" . $name;
}

sub _class_generator {
    my (%testParams) = @_;
    my $prefix = "__MAFT::Class::";
    my $className = $prefix . ( $testParams{name} || _randomName );

    #diag "CLASS NAME:" . $className;

    my $body    = $testParams{body} // '';
    my $extends = '';

    if ( $testParams{extends} ) {
        my @extList =
          ref( $testParams{extends} )
          ? @{ $testParams{extends} }
          : ( $testParams{extends} );
        $extends =
          "extends qw<" . join( " ", map { $prefix . $_ } @extList ) . ">;";
    }

    my $rc = eval <<CLASS;
package $className;

use Moo;
$extends

$body

1;
CLASS
    die $@ if $@;
    return $className;
}

sub _role_generator {
    my (%testParams) = @_;
    my $prefix = "__MAFT::Role::";
    my $testName  = $testParams{name} || _randomName;
    my $roleName  = $prefix . $testName;
    my $className = "__MAFT::RoleClass::" . $testName;

    my $body = $testParams{body} // '';
    my $with = '';

    if ( $testParams{extends} ) {
        my @extList =
          ref( $testParams{extends} )
          ? @{ $testParams{extends} }
          : ( $testParams{extends} );
        $with = "with qw<" . join( " ", map { $prefix . $_ } @extList ) . ">;";
    }

    my $code = <<ROLE;
package ${roleName};

use Moo::Role;
$with

$body

1;
ROLE
    my $rc = eval $code;
    die $@ if $@;

    $rc = eval <<CLASS;
package ${className};

use Moo;
with qw<${roleName}>;

1;
CLASS
    die $@ if $@;
    return $className;
}

1;
