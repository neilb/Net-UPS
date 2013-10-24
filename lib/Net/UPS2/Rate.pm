package Net::UPS2::Rate;
use strict;
use warnings;
use Moo;
use 5.10.0;
use Types::Standard qw(Str ArrayRef);
use Net::UPS2::Types ':types';

has unit => (
    is => 'ro',
    isa => MeasurementUnit,
    required => 1,
);

has billing_weight => (
    is => 'ro',
    isa => Measure,
    required => 0,
);

has total_charges => (
    is => 'ro',
    isa => Measure,
    required => 1,
);

has total_charges_currency => (
    is => 'ro',
    isa => Currency,
    required => 1,
);

has rated_package => (
    is => 'ro',
    isa => Package,
    required => 1,
);

has service => (
    is => 'ro',
    isa => Service,
    required => 1,
);

has from => (
    is => 'ro',
    isa => Address,
    required => 1,
);

has to => (
    is => 'ro',
    isa => Address,
    required => 1,
);

1;
