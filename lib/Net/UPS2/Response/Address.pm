package Net::UPS2::Response::Address;
use strict;
use warnings;
use Moo;
use Types::Standard qw(ArrayRef HashRef);
use Net::UPS2::Types qw(:types);
use namespace::autoclean;

has addresses => (
    is => 'ro',
    isa => ArrayRef[Address],
    required => 1,
);

has warnings => (
    is => 'ro',
    isa => HashRef,
    required => 0,
);

1;
