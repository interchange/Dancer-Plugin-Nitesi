package Dancer::Plugin::Nitesi::Cart::DBI;

use strict;
use warnings;

=head1 NAME

Dancer::Plugin::Nitesi::Cart::DBI - DBI cart backend for Nitesi

=cut

use Nitesi::Query::DBI;

use Dancer qw/session hook/;
use Dancer::Plugin::Database;

use base 'Nitesi::Cart';

=head1 METHODS

=head2 init

=cut

sub init {
    my ($self, %args) = @_;
    my (%q_args);

    $self->{dbh} = database();
    %q_args = (dbh => $self->{dbh});

    if ($args{settings}->{log_queries}) {
	$q_args{log_queries} = sub {
	    Dancer::Logger::debug(@_);
	};
    };

    $self->{settings} = $args{settings} || {};
    $self->{sqla} = Nitesi::Query::DBI->new(%q_args);

    hook 'after_cart_add' => sub {$self->_after_cart_add(@_)};
    hook 'after_cart_update' => sub {$self->_after_cart_update(@_)};
    hook 'after_cart_remove' => sub {$self->_after_cart_remove(@_)};
    hook 'after_cart_rename' => sub {$self->_after_cart_rename(@_)};
    hook 'after_cart_clear' => sub {$self->_after_cart_clear(@_)};
}

=head2 load

Loads cart from database. 

=cut

sub load {
    my ($self, %args) = @_;
    my ($uid, $result, $code, %specs);

    # check whether user is authenticated or not
    unless ($uid = $args{uid} || 0) {
	return;
    }

    $self->{uid} = $uid;

    # determine cart code
    $code = $self->{sqla}->select_field(table => 'carts', field => 'code', where => {name => $self->name, uid => $uid});
    
    unless ($code) {
	$self->{id} = 0;
	return;
    }
    $self->{id} = $code;

    # build query for item retrieval
    %specs = (fields => $self->{settings}->{fields} || 
	      [qw/products.sku products.name cart_products.quantity/],
	      join => $self->{settings}->{join} ||
	      [qw/carts code=cart cart_products sku=sku products/],
	      where => {'carts.name' => $self->name, uid => $uid});	      

    # retrieve items from database
    $result = $self->{sqla}->select(%specs);

    $self->seed($result);
}

=head2 save

No-op, as all cart changes are saved through hooks to the database.

=cut

sub save {
    return 1;
}

sub _after_cart_add {
    my ($self, @args) = @_;
    my ($item, $update, $record);

    unless ($self eq $args[0]) {
	# not our cart
	return;
    }

    $item = $args[1];
    $update = $args[2];

    unless ($self->{code}) {
	# need to create cart first
	$self->{sqla}->insert('carts', {name => $self->name,
					uid => $self->{uid}});
  
	# determine cart code
	$self->{code} = $self->{sqla}->select_field(table => 'carts', field => 'code', 
						    where => {name => $self->name, uid => $self->{uid}});
    }

    if ($update) {
	# update item in database
	$record = {quantity => $item->{quantity}};
	$self->{sqla}->update('cart_products', $record, {cart => $self->{code}, sku => $item->{sku}});
    }
    else {
	# add new item to database
	$record = {cart => $self->{code}, sku => $item->{sku}, quantity => $item->{quantity}, position => 0};
	$self->{sqla}->insert('cart_products', $record);
    }
}

sub _after_cart_update {
    my ($self, @args) = @_;
    my ($item, $new_item, $count);

    unless ($self eq $args[0]) {
	# not our cart
	return;
    }

    $item = $args[1];
    $new_item = $args[2];

    # update item in database
    Dancer::Logger::debug("Updating cart products with: ", $new_item);

    $count = $self->{sqla}->update(table => 'cart_products', 
				   set => $new_item, 
				   where => {cart => $self->{id}, sku => $item->{sku}});

    Dancer::Logger::debug("Items updated: $count.");
}

sub _after_cart_remove {
    my ($self, @args) = @_;
    my ($item);

    unless ($self eq $args[0]) {
	# not our cart
	return;
    }

    $item = $args[1];

    $self->{sqla}->delete('cart_products', {cart => $self->{id}, sku => $item->{sku}});
}

sub _after_cart_rename {
    my ($self, @args) = @_;

    unless ($self eq $args[0]) {
	# not our cart
	return;
    }

    $self->{sqla}->update('carts', {name => $args[2]}, {code => $self->{id}});    
}

sub _after_cart_clear {
    my ($self, @args) = @_;

    unless ($self eq $args[0]) {
	# not our cart
	return;
    }

    $self->{sqla}->delete('cart_products', {cart => $self->{id}});
}

=head1 AUTHOR

Stefan Hornburg (Racke), <racke@linuxia.de>

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Stefan Hornburg (Racke) <racke@linuxia.de>.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
