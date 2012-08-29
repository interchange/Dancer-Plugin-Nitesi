#! perl

use Test::More tests => 2;
use Dancer::Test;

use Dancer::Plugin::Nitesi;

my $ret;

$ret = cart->add(sku => 'FOO', name => 'Foo Shoes', price => 5, quantity => 2);

ok ($ret, "Add Foo Shoes to cart.")
    || diag "Failed to add foo shoes.";

$ret = cart->count;

ok($ret == 1, "Checking cart count after adding two FOOs.")
    || diag "Count is $ret instead of 1.";
