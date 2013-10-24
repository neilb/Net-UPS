package Net::UPS2::Package;
use strict;
use warnings;
use Moo;
use Type::Params qw(compile);
use Types::Standard qw(Int Object);
use Net::UPS2::Types ':types';
use Net::UPS2::Exception;
use namespace::autoclean;
use 5.10.0;

has id => (
    is => 'rw',
    isa => Int,
);

has packaging_type => (
    is => 'ro',
    isa => PackagingType,
    default => sub { 'PACKAGE' },
);

has measurement_system => (
    is => 'ro',
    isa => MeasurementSystem,
    required => 1,
);

has length => (
    is => 'ro',
    isa => Measure,
);

has width => (
    is => 'ro',
    isa => Measure,
);

has height => (
    is => 'ro',
    isa => Measure,
);

has weight => (
    is => 'ro',
    isa => Measure,
);

my %code_for_packaging_type = (
    LETTER          => '01',
    PACKAGE         => '02',
    TUBE            => '03',
    UPS_PAK         => '04',
    UPS_EXPRESS_BOX => '21',
    UPS_25KG_BOX    => '24',
    UPS_10KG_BOX    => '25'
);

sub linear_unit {
    state $argcheck = compile(Object);
    my ($self) = $argcheck->(@_);

    $self->measurement_system eq 'metric' ? 'CM' : 'IN';
}

sub weight_unit {
    state $argcheck = compile(Object);
    my ($self) = $argcheck->(@_);

    $self->measurement_system eq 'metric' ? 'KGS' : 'LBS';
}

sub as_hash {
    state $argcheck = compile(Object);
    my ($self) = $argcheck->(@_);

    my %data = (
        PackagingType       => {
            Code => $code_for_packaging_type{$self->packaging_type},
        },
    );

    if ( $self->length || $self->width || $self->height ) {
        $data{Dimensions} = {
            UnitOfMeasurement => {
                Code => $self->linear_unit,
            }
        };

        if ( $self->length ) {
            $data{Dimensions}->{Length}= $self->length;
        }
        if ( $self->width ) {
            $data{Dimensions}->{Width} = $self->width;
        }
        if ( $self->height ) {
            $data{Dimensions}->{Height} = $self->height;
        }
    }

    if ( $self->weight ) {
        $data{PackageWeight} = {
            UnitOfMeasurement => {
                Code => $self->weight_unit,
            },
            Weight => $self->weight,
        };
    }

    if (my $oversized = $self->is_oversized ) {
        $data{OversizePackage} = $oversized;
    }

    return \%data;
}

sub is_oversized {
    state $argcheck = compile(Object);
    my ($self) = $argcheck->(@_);

    unless ( $self->width && $self->height && $self->length && $self->weight) {
        return 0;
    }

    my @sides = sort { $a <=> $b } ($self->length, $self->width, $self->height);
    my $len = pop(@sides);  # Get longest side
    my $girth = ((2 * $sides[0]) + (2 * $sides[1]));
    my $size = $len + $girth;

    my ($max_len,$max_weight,$max_size,
        $min_size,
        $os1_size,$os1_weight,
        $os2_size,$os2_weight,
        $os3_size,$os3_weight) =
            $self->measurement_system eq 'english' ?
                ( 108, 150, 165,
                  84,
                  108, 30,
                  130, 70,
                  165, 90 ) :
                ( 270, 70, 419,
                  210,
                  270, 10,
                  330, 32,
                  419, 40 );

    if ($len > $max_len or $self->weight > $max_weight or $size > $max_size) {
        Net::UPS2::Exception::BadPackage->throw({package=>$self});
    }

    return 0 if ( $size <= $min_size ); # Below OS1
    if ($size <= $os1_size) { # OS1 pgk is billed for 30lbs
        return (($self->weight < $os1_weight) ? 1 : 0); # Not OS1 if weight > 30lbs
    }
    if ($size <= $os2_size) { # OS2 pgk is billed for 70lbs
        return (($self->weight < $os2_weight) ? 2 : 0); # Not OS2 if weight > 70lbs
    }
    if ($size <= $os3_size) { # OS3 pgk is billed for 90lbs
        return (($self->weight < $os3_weight) ? 3 : 0); # Not OS3 if weight > 90lbs
    }
}

1;

