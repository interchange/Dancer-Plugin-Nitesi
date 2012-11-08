package Dancer::Plugin::Nitesi;

use 5.0006;
use strict;
use warnings;

use Nitesi::Account::Manager;
use Nitesi::Product;
use Nitesi::Cart;
use Nitesi::Class;
use Nitesi::Query::DBI;

use Moo::Role;

use Dancer qw(:syntax !before !after);
use Dancer::Plugin;
use Dancer::Plugin::Database;

=head1 NAME

Dancer::Plugin::Nitesi - Nitesi Shop Machine plugin for Dancer

=head1 VERSION

Version 0.0060

=cut

our $VERSION = '0.0060';

=head1 SYNOPSIS

    use Dancer::Plugin::Nitesi;

    cart->add({sku => 'ABC', name => 'Foobar', quantity => 1, price => 42});
    cart->items();
    cart->clear();

    account->login(username => 'frank@nitesi.com', password => 'nevairbe');
    account->acl(check => 'view_prices');
    account->logout();

=head1 DESCRIPTION

This dancer plugin gives you access to the account and cart functions of
the Nitesi shop machine.

=head1 CARTS

The cart keyword returns a L<Nitesi::Cart> object with the corresponding methods. 

You can use multiple carts like that:

    cart('wishlist')->add({sku => 'ABC', name => 'Foobar', quantity => 1, price => 42});
    cart('wishlist')->total;

The DBI backend (L<Dancer::Plugin::Nitesi::Cart::DBI>) allows you to load carts
of arbitrary users.

    cart('', 123)->items;

=head1 ACCOUNTS

The account keyword returns a L<Nitesi::Account::Manager> object with the
corresponding methods.

Login to an account:

    account->login(username => 'frank@nitesi.com', password => 'nevairbe');

Logout:

    account->logout();

Check permissions:

    account->acl(check => 'view_prices');

Change password for current account:

    account->password('nevairbe');

Change password for other account:

    account->password(username => 'frank@nitesi.com', password => 'nevairbe');

Create account:

    account->create(email => 'fina@nitesi.com');

=head1 HOOKS

This plugin installs the following hooks:

=head2 Add to cart

The functions registered for these hooks receive the cart object
and the item to be added as parameters.

=over 4

=item before_cart_add_validate

Triggered before item is validated for adding to the cart.

=item before_cart_add

Triggered before item is added to the cart.

=item after_cart_add

Triggered after item is added to the cart.
Used by DBI backend to save item to the database.

=back

=head2 Update cart

The functions registered for these hooks receive the cart object,
the current item in the cart and the updated item.

=over 4

=item before_cart_update

Triggered before cart item is updated (changing quantity).

=item after_cart_update

Triggered after cart item is updated (changing quantity).
Used by DBI backend to update item to the database.

=back

=head2 Remove from cart

The functions registered for these hooks receive the cart object
and the item to be added as parameters.

=over 4

=item before_cart_remove_validate

Triggered before item is validated for removal.
Receives cart object and item SKU.

=item before_cart_remove

Triggered before item is removed from the cart.
Receives cart object and item.

=item after_cart_remove

Triggered after item is removed from the cart.
Used by DBI backend to delete item from the database.
Receives cart object and item.

=back

=head2 Clear cart

=over 4

=item before_cart_clear

Triggered before cart is cleared.

=item after_cart_clear

Triggered after cart is cleared.

=back

=head2 Rename cart

The functions registered for these hooks receive the cart object,
the old name and the new name.

=over 4

=item before_cart_rename

Triggered before cart is renamed.

=item after_cart_rename

Triggered after cart is renamed.

=back

=head1 CONFIGURATION

The default configuration is as follows:

    plugins:
      Nitesi:
        Account:
          Session:
            Key: account
          Provider: DBI
      Cart:
        Backend: Session
      Product:
        backend: DBI
        table: products
        key: sku

=head2 ACCOUNT

=head3 Connection

The connection used by L<Dancer::Plugin::Database> can be set
as follows:

    plugins:
      Nitesi:
        Account:
          Provider: DBI
          Connection: shop

=head3 Fields

Extra fields can be retrieved from the account provider and
put into the session after a successful login:

    plugins:
      Nitesi:
        Account:
          Provider: DBI
          Fields: first_name,last_name,city

=cut

register_hook(qw/before_cart_add_validate
                 before_cart_add after_cart_add
                 before_cart_update after_cart_update
                 before_cart_remove_validate
                 before_cart_remove after_cart_remove
                 before_cart_rename after_cart_rename
                 before_cart_clear after_cart_clear
                /);

my $settings = undef;

my %acct_providers;
my %carts;

hook 'after' => sub {
    my $carts;

    # save all carts
    $carts = vars->{'nitesi_carts'} || {};

    for (keys %$carts) {
	$carts->{$_}->save();
    }
};

register account => \&_account;

sub _account {
    my $acct;

    unless (vars->{'nitesi_account'}) {
        # not yet used in this request
        $acct = Nitesi::Account::Manager->new(provider_sub => \&_load_account_providers,
                                              session_sub => \&_update_session);
        $acct->init_from_session;

        var nitesi_account => $acct;
    }

    return vars->{'nitesi_account'};
};

sub _api_object {
    my (%args) = @_;
    my ($api_class, $api_object, $settings_class, $backend, $sname, $provider,
        $provider_settings, $o_settings, $backend_settings, @roles);

    _load_settings();

    $sname = ucfirst($args{name});

    # determine backend
    if ($args{backend}) {
        $backend = $args{backend};
    }
    elsif (exists $settings->{$sname}->{providers}) {
        if ($provider = $settings->{Product}->{default_provider}) {
            $provider_settings =  $settings->{Product}->{providers}->{$provider};

            $backend = $provider_settings->{backend} || 'DBI';
        }
    }
    else {
        $backend = 'DBI';
    }

    # check whether base class for this object is overridden in the settings
    if (exists $settings->{$sname}->{class}) {
        $api_class = $settings->{$sname}->{class};
    }
    else {
        $api_class = $args{class};
    }

    # create API object
    my (%api_info, $o_key);

    $api_object = Nitesi::Class->instantiate($api_class,
					     api_class => $api_class,
					     api_name => $args{name});

    unless ($api_object) {
        die "Failed to create class $api_class: $@";
    }

    $api_info{$api_class} = $api_object->api_info;
    $o_key = $api_info{$api_class}->{key};

    # load Dancer settings for this backend
    $settings_class = "Dancer::Plugin::Nitesi::Backend::$backend";

    $o_settings = Nitesi::Class->instantiate($settings_class);
    $backend_settings = $o_settings->params;

    # load roles for this API object
    for my $role_name (@{$args{roles} || []}) {
        Nitesi::Class->load($role_name);
        my $api_func = lc($role_name);
        $api_func =~ s/^(.*)::([^:]+)$/$2/;
        $api_func .= '_api_info';
        $api_info{$role_name} = $role_name->$api_func;
        push (@roles, $role_name);
    }

    # load backend class
    my $backend_class = "Nitesi::Backend::$backend";
    Nitesi::Class->load($backend_class);

    # apply backend role to navigation object
    my ($key, $value);

    Moo::Role->apply_roles_to_object($api_object, @roles, $backend_class);

    while (($key, $value) = each %$backend_settings) {
        $api_object->$key($value);
    }

    if ($settings->{$sname}->{field_map}) {
        $api_object->field_map($settings->{$sname}->{field_map});
    }

    $api_object->api_info(\%api_info);

    if ($args{$o_key}) {
        $api_object->$o_key($args{$o_key});
    }

    return $api_object;
}

register shop_address => sub {
    my ($aid) = @_;
    my ($address);

    $address = _api_object(name => 'address',
                           class => 'Nitesi::Address',
                           aid => $aid,
        );

    return $address;
};

register shop_merchandising => sub {
    my ($code) = @_;
    my ($object);

    $object = _api_object(name => 'merchandising',
                          class => 'Nitesi::Merchandising',
                          code => $code,
        );

    return $object;
};

register shop_transaction => sub {
    my ($code) = @_;
    my ($transaction);

    $transaction = _api_object(name => 'transaction',
                               class => 'Nitesi::Transaction',
                               code => $code,
        );

    return $transaction;
};

register shop_navigation => sub {
    my ($code) = @_;
    my ($navigation);

    $navigation = _api_object(name => 'navigation',
                              class => 'Nitesi::Navigation',
                              code => $code,
        );

    return $navigation;
};

register shop_product => sub {
    my ($sku, $backend) = @_;
    my (%api_params, $backend_params, $settings_class, $o_settings, $backend_class, $o_backend,
	$provider, $provider_settings, $backend_settings);

    %api_params = (name => 'product',
                   class => 'Nitesi::Product',
                   roles => ['Nitesi::Inventory'],
        );

    if (defined $sku) {
        $api_params{sku} = $sku;
    }

    return _api_object(%api_params);
};

register shop_media => sub {
    my ($code) = @_;
    my ($object);
     
    $object = _api_object(name => 'media',
                               class => 'Nitesi::Media',
                               code => $code,
        );
    
    return $object;
};

register cart => sub {
    my ($name, $id, $token);

    $name = shift || 'main';
    $id = shift;

    if (defined $id) {
	$token = "$name\0$id";
    }
    else {
	$token = $name;
    }

    unless (exists vars->{nitesi_carts}->{$token}) {
	# instantiate cart
	vars->{nitesi_carts}->{$token} = _create_cart($name, $id);
    }

    return vars->{'nitesi_carts'}->{$token};
};

register query => sub {
    my ($name, $arg, $q, $dbh);

    if (@_) {
        $name = shift;
        $arg = $name;
    }
    else {
        $name = '';
        $arg = undef;
    }
    
    unless (exists vars->{'nitesi_query'}->{$name}) {
        # not yet used in this request
        unless ($dbh = database($arg)) {
            die "No database handle for database '$name'";
        }

        $q = Nitesi::Query::DBI->new(dbh => $dbh);
        vars->{'nitesi_query'}->{$name} = $q;
    }

    return vars->{nitesi_query}->{$name};
};

register_plugin;

sub _load_settings {
    $settings ||= plugin_setting;
}

sub _load_account_providers {
    _load_settings();

    # setup account providers
    if (exists $settings->{Account}->{Provider}) {
        if ($settings->{Account}->{Provider} eq 'DBI') {
            return [['Nitesi::Account::Provider::DBI',
                     dbh => database($settings->{Account}->{Connection}),
                     fields => _config_to_array($settings->{Account}->{Fields}),
                     inactive => $settings->{Account}->{inactive},
                    ]];
        }
        else {
            my $provider_class = $settings->{Account}->{Provider};

            unless ($provider_class =~ /::/) {
                $provider_class = "Nitesi::Account::Provider::$provider_class";
            }

            my %account_init = %{$settings->{Account}};

            delete $account_init{Provider};

            return [[$provider_class, %account_init]];
        }
    }

    # DBI provider is the default
    return [['Nitesi::Account::Provider::DBI',
             dbh => database]];
}

sub _config_to_array {
    my $config = shift;
    my @values;

    if (defined $config) {
	@values = split(/\s*,\s*/, $config);
	return \@values;
    }

    return [];
}

sub _create_cart {
    my ($name, $id) = @_;
    my ($backend, $backend_class, $cart, $cart_settings);

    _load_settings();

    if (exists $settings->{Cart}->{Backend}) {
	$backend = $settings->{Cart}->{Backend};
    }
    else {
	$backend = 'Session';
    }

    # check for specific settings for this cart name
    if (exists $settings->{Cart}->{Carts}) {
        my $sref = $settings->{Cart}->{Carts};

        if (ref($sref) eq 'ARRAY') {
            # walk through settings
            for my $try (@$sref) {
                if (exists $try->{name}
                    && $name eq $try->{name}) {
                    $cart_settings = $try;
                    last;
                }
                if (exists $try->{match}) {
                    my $match = qr/$try->{match}/;

                    if ($name =~ /$match/) {
                        $cart_settings = $try;
                        last;
                    }
                }
            }
        }
        elsif (ref($sref) eq 'HASH') {
            if (exists $settings->{Cart}->{Carts}->{$name}) {
                $cart_settings = $settings->{Cart}->{Carts}->{$name};
            }
        }
        else {
            die "Invalid cart settings.";
        }
    }

    # determine backend class name
    if ($backend =~ /::/) {
	$backend_class = $backend;
    }
    else {
	$backend_class = __PACKAGE__ . "::Cart::$backend";
    }

    $cart = Nitesi::Class->instantiate($backend_class,
				       name => $name,
                                       settings => $cart_settings,
				       run_hooks => sub {execute_hook(@_)});

    $cart->load(uid => $id || _account()->uid);

    return $cart;
}

sub _update_session {
    my ($function, $acct) = @_;
    my ($key, $sref);

    _load_settings();

    # determine session key
    $key = $settings->{Account}->{Session}->{Key} || 'user';

    $function ||= '';

    if ($function eq 'init') {
	# initialize user related information
	session $key => $acct;
    }
    elsif ($function eq 'update') {
	# update user related information (retrieve current state first)
	$sref = session $key;

	for my $name (keys %$acct) {
	    $sref->{$name} = $acct->{$name};
	}

	session $key => $sref;

	return $sref;
    }
    elsif ($function eq 'destroy') {
	# destroy user related information
	session $key => undef;
    }
    else {
	# return user related information
	return session $key;
    }
}


=head1 CAVEATS

Please anticipate API changes in this early state of development.

=head1 AUTHOR

Stefan Hornburg (Racke), C<racke@linuxia.de>

=head1 BUGS

Please report any bugs or feature requests to C<bug-nitesi at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dancer-Plugin-Nitesi>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer-Plugin-Nitesi

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dancer-Plugin-Nitesi>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer-Plugin-Nitesi>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Dancer-Plugin-Nitesi>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer-Plugin-Nitesi/>

=back


=head1 ACKNOWLEDGEMENTS

The L<Dancer> developers and community for their great application framework
and for their quick and competent support.

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2012 Stefan Hornburg (Racke).

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=head1 SEE ALSO

L<Nitesi>

=cut

1;
