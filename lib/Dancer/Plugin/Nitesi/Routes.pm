package Dancer::Plugin::Nitesi::Routes;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Plugin::Nitesi;
use Dancer::Plugin::Nitesi::Routes::Cart;

=head1 NAME

Dancer::Plugin::Nitesi::Routes - Routes for Nitesi Shop Machine

=head2 CONFIGURATION

The template for each route type can be configured:

    plugins:
      Nitesi::Routes:
        cart:
          template: cart
        product:
          template: product

This sample configuration shows the current defaults.

=cut

register shop_setup_routes => sub {
    _setup_routes();
};

register_plugin;

our %route_defaults = (cart => {template => 'cart'},
                       product => {template => 'product'});

sub _setup_routes {
    my $plugin_config = plugin_setting;

    # update settings with defaults
    my $routes_config = _config_routes($plugin_config, \%route_defaults);

    # routes for cart
    my $cart_sub = Dancer::Plugin::Nitesi::Routes::Cart::cart_route($routes_config);
    get '/cart' => $cart_sub;
    post '/cart' => $cart_sub;

    # fallback route for flypage and navigation
    get qr{/(?<path>.*)} => sub {
        my $path = captures->{'path'};

        # first check for a matching product
        my $product = shop_product($path)->load;

        if ($product) {
            if ($product->inactive) {
                # discontinued
                status 'not_found';
                forward 404;
            }
            else {
                # flypage
                return template $routes_config->{product}->{template}, $product;
            }
        }

        # first check for navigation item
        my $result = shop_navigation->search(where => {uri => $path});

        if (@$result > 1) {
            die "Ambigious result on path $path.";
        }

        if (@$result == 1) {
            # navigation item found
            my $pkeys = shop_navigation($result->[0]->{code})->assigned(shop_product);

            my $products = [map {shop_product($_)->dump} @$pkeys];

            return template 'listing', {%{$result->[0]},
                                        products => $products,
                                       };
        }

        # display not_found page
        status 'not_found';
        forward 404;
    };
}

sub _config_routes {
    my ($settings, $defaults) = @_;
    my ($key, $vref, $name, $value);

    while (($key, $vref) = each %$defaults) {
        while (($name, $value) = each %$vref) {
            unless (exists $settings->{$key}->{$name}) {
                $settings->{$key}->{$name} = $value;
            }
        }
    }

    return $settings;
}

1;
