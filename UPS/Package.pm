package Net::UPS::Package;

# $Id: Package.pm,v 1.5 2005/09/07 00:09:14 sherzodr Exp $

=head1 NAME

Net::UPS::Package - Class representing a UPS Package

=head1 SYNOPSIS

    $pkg = Net::UPS::Package->new();
    $pkg->packaging_type('PACKAGE');
    $pkg->measurement_system('metric');
    $pkg->length(40);
    $pkg->width(30);
    $pkg->height(2);
    $pkg->weight(10);

=head1 DESCRIPTION

Net::UPS::Package represents a single UPS package. In addition to the above attributes, I<id> attribute will be set once package is submitted for a rate quote. I<id> starts at I<1>, and will be incremented by one for each subsequent package submitted at single request. The purpose of this attribute is still not clear. Comments are welcome.

=head1 METHODS

In addition to all the aforementioned attributes, following method(s) are supported

=over 4

=cut

use strict;
use Carp ( 'croak' );
use XML::Simple;
use Class::Struct;

struct(
    id                  => '$',
    packaging_type      => '$',
    measurement_system  => '$',
    length              => '$',
    width               => '$',
    height              => '$',
    weight              => '$'
);


sub PACKAGE_CODES() {
    return {
        LETTER          => '01',
        PACKAGE         => '02',
        TUBE            => '03',
        UPS_PAK         => '04',
        UPS_EXPRESS_BOX => '21',
        UPS_25KG_BOX    => '24',
        UPS_10KG_BOX    => '25'
    };
}

sub _packaging2code {
    my $self    = shift;
    my $label   = shift;

    unless ( defined $label ) {
        croak "_packaging2code(): usage error";
    }
    $label =~ s/\s+/_/g;
    $label =~ s/\W+//g;
    my $code = PACKAGE_CODES->{$label};
    unless ( defined $code ) {
        croak "Nothing known about package type '$label'";
    }
    return $code;
}





sub as_hash {
    my $self = shift;

    my $measurement_system = $self->measurement_system || 'english';

    my $weight_measure  = ($measurement_system eq 'metric') ? 'KGS' : 'LBS';
    my $length_measure  = ($measurement_system eq 'metric') ? 'CM'  : 'IN';
    my %data = (
        Package => {
            PackagingType       => {  
                Code => $self->packaging_type ? sprintf("%02d", $self->_packaging2code($self->packaging_type)) : '02',
            },
            Dimensions          => {
                UnitOfMeasurement => {
                    Code => $length_measure
                }
            },
            DimensionalWeight   => {
                UnitOfMeasurement => {
                    Code => $weight_measure
                }
            },
            PackageWeight       => {
                UnitOfMeasurement => {
                    Code => $weight_measure
                }
            }
        }
    );
    if ( $self->length ) {
        $data{Package}->{Dimensions}->{Length}= $self->length;
    }
    if ( $self->width ) {
        $data{Package}->{Dimensions}->{Width} = $self->width;
    }
    if ( $self->height ) {
        $data{Package}->{Dimensions}->{Height} = $self->height;
    }
    if ( $self->weight ) {
        $data{Package}->{PackageWeight}->{Weight} = $self->weight;
    }
    if (my $oversized = $self->is_oversized ) {
        $data{Package}->{OversizePackage} = $oversized;
    }
    return \%data;
}


=item is_oversized

Convenience method. Return value indicates if the package is oversized, and if so, its oversize level. Possible return values are I<0>, I<1>, I<2> and I<3>. I<0> means not oversized.

=cut

sub is_oversized {
    my $self = shift;

    unless ( $self->width && $self->height && $self->length && $self->weight) {
        return 0;
    }
    my $girth = $self->length + $self->width + $self->height;
    return 0 if ( $girth < 84 );
    if ( ($girth < 108) && ($self->weight < 30) ) {
        return 1;
    }
    if ( ($girth < 130) && ($self->weight < 70) ) {
        return 2;
    }
    if ( ($girth < 165) && ($self->weight < 90) ) {
        return 3;
    }
    croak "Such package size/weight is not supported";
}





sub as_XML {
    my $self = shift;
    return XMLout( $self->as_hash, NoAttr=>1, KeepRoot=>1, SuppressEmpty=>1 )
}


1;

__END__


=back

=head1 AUTHOR AND LICENSING

For support and licensing information refer to L<Net::UPS|Net::UPS/"AUTHOR">

=cut
