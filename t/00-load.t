#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Dancer::Plugin::Nitesi' ) || print "Bail out!
";
}

diag( "Testing Dancer::Plugin::Nitesi $Dancer::Plugin::Nitesi::VERSION, Perl $], $^X" );
