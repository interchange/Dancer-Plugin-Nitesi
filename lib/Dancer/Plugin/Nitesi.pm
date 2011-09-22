package Dancer::Plugin::Nitesi;

use 5.0006;
use strict;
use warnings;

use Nitesi::Account::Manager;
use Nitesi::Cart;
use Nitesi::Class;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Plugin::Database;

=head1 NAME

Dancer::Plugin::Nitesi - Nitesi Shop Machine plugin for Dancer

=head1 VERSION

Version 0.0001

=cut

our $VERSION = '0.0001';

=head1 SYNOPSIS

    use Dancer::Plugin::Nitesi;

    cart->add({sku => 'ABC', name => 'Foobar', quantity => 1, price => 42});
    cart->items();

    account->login(username => 'frank@nitesi.com', password => 'nevairbe');
    account->acl(check => 'view_prices');
    account->logout();

=head1 CARTS

The cart keyword returns a L<Nitesi::Cart> object with the corresponding methods. 

You can use multiple carts like that:

    cart('wishlist')->add({sku => 'ABC', name => 'Foobar', quantity => 1, price => 42});
    cart('wishlist')->total;

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

=cut

Dancer::Factory::Hook->instance->install_hooks(qw/before_cart_add after_cart_add/);

my $settings = undef;

my %acct_providers;
my %carts;

before sub {
    # find out which backend we are using
    my ($backend, $backend_class, $backend_obj);

    _load_settings() unless $settings;
};

after sub {
    my $carts;

    # save all carts
    $carts = vars->{'nitesi_carts'} || {};

    for (keys %$carts) {
	$carts->{$_}->save();
    }
};

register account => sub {
    my $acct;

    unless (vars->{'nitesi_account'}) {
	# not yet used in this request
	$acct = Nitesi::Account::Manager->instance(provider_sub => \&_load_account_providers, 
						   session_sub => \&_update_session);
	$acct->init_from_session;

	var nitesi_account => $acct;
    }

    return vars->{'nitesi_account'};
};

register cart => sub {
    my $name;

    if (@_) {
	$name = shift;
    }
    else {
	$name = 'main';
    }

    unless (exists vars->{nitesi_carts}->{$name}) {
	# instantiate cart
	vars->{nitesi_carts}->{$name} = _create_cart($name);
    }

    return vars->{'nitesi_carts'}->{$name};
};

register_plugin;

sub _load_settings {
    $settings = plugin_setting;
}

sub _load_account_providers {
    # setup account providers
    if (exists $settings->{Account}->{Provider}) {
	if ($settings->{Account}->{Provider} eq 'DBI') {
	    # we need to pass $dbh
	    return [['Nitesi::Account::Provider::DBI',
		     dbh => database()]];
	}
    }
}

sub _create_cart {
    my $name = shift;
    my ($backend, $backend_class, $cart);

    if (exists $settings->{Cart}->{Backend}) {
	$backend = $settings->{Cart}->{Backend};
    }
    else {
	$backend = 'Session';
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
				       run_hooks => sub {Dancer::Factory::Hook->instance->execute_hooks(@_)});

    $cart->load();

    return $cart;
}

sub _update_session {
    my ($function, $acct) = @_;
    my ($key, $sref);

    # determine session key
    $key = $settings->{Account}->{Session}->{Key} || 'user';

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
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Nitesi>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Nitesi

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Nitesi>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Nitesi>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Nitesi>

=item * Search CPAN

L<http://search.cpan.org/dist/Nitesi/>

=back


=head1 ACKNOWLEDGEMENTS

The L<Dancer> developers and community for their great application framework
and for their quick and competent support.

=head1 LICENSE AND COPYRIGHT

Copyright 2010-2011 Stefan Hornburg (Racke).

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=head1 SEE ALSO

L<Nitesi>

=cut

1;
