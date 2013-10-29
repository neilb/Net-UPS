package Net::UPS2::Address;
use strict;
use warnings;
use Moo;
use 5.10.0;
use Types::Standard qw(Str Int Bool StrictNum);
use Net::UPS2::Types ':types';

has quality => (
    is => 'ro',
    isa => StrictNum,
    required => 0,
);

has city => (
    is => 'ro',
    isa => Str,
    required => 0,
);

has postal_code => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has state => (
    is => 'ro',
    isa => Str,
    required => 0,
);

has country_code => (
    is => 'ro',
    isa => Str,
    required => 0,
);

has is_residential => (
    is => 'ro',
    isa => Bool,
    required => 0,
);

sub is_exact_match {
    my $self = shift;
    return unless $self->quality();
    return ($self->quality == 1);
}


sub is_very_close_match {
    my $self = shift;
    return unless $self->quality();
    return ($self->quality >= 0.95);
}

sub is_close_match {
    my $self = shift;
    return unless $self->quality();
    return ($self->quality >= 0.90);
}

sub is_possible_match {
    my $self = shift;
    return unless $self->quality();
    return ($self->quality >= 0.90);
}

sub is_poor_match {
    my $self = shift;
    return unless $self->quality();
    return ($self->quality <= 0.69);
}

sub as_hash {
    my $self = shift;

    my %data = (
        Address => {
            CountryCode => $self->country_code || "US",
            PostalCode  => $self->postal_code,
            ( $self->city ? ( City => $self->city) : () ),
            ( $self->state ? ( StateProvinceCode => $self->state) : () ),
            ( $self->is_residential ? ( ResidentialAddressIndicator => undef ) : () ),
        }
    );

    return \%data;
}

1;
