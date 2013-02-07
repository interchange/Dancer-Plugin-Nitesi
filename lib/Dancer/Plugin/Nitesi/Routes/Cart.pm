package Dancer::Plugin::Nitesi::Routes::Cart;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Plugin::Nitesi;

=head1 NAME

Dancer::Plugin::Nitesi::Routes::Cart - Cart routes for Nitesi Shop Machine

=cut

register_hook 'before_cart_display';

=head1 FUNCTIONS

=head2 cart_route

Returns the cart route based on the passed routes configuration.

=cut

sub cart_route {
    my $routes_config = shift;

    return sub {
        my %values;

        # call before_cart_display route so template tokens
        # can be injected
        execute_hook('before_cart_display', \%values);

        template $routes_config->{cart}->{template}, \%values;
    }
}

1;
