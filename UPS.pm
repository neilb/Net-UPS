package Net::UPS;

# $Id: UPS.pm,v 1.6 2005/09/07 00:09:13 sherzodr Exp $

=head1 NAME

Net::UPS - Implementation of UPS Online Tools API in Perl

=head1 SYNOPSIS

    use Net::UPS;
    $ups = Net::UPS->new($userid, $password, $accesskey);
    $rate = $ups->rate($from_zip, $to_zip, $package);
    printf("Shipping this package $from_zip => $to_zip will cost you \$.2f\n", $rate->total_charges);

=head1 WARNING

Although functional, this is an alpha software. Net::UPS is still under testing stage, and interface can change in the future without any notice. Until this warning sign is removed and Net::UPS version becomes at least 1.0, you are discouraged from using this software in production environment, or do not expect backward-compatible upgrades!

=head1 DESCRIPTION

Net::UPS implements UPS' Online Tools API in Perl. In a nutshell, Net::UPS knows how to retrieve rates and service information for shipping packages using UPS, as well as for validating U.S. addresses.

This manual is optimized to be used as a quick reference. If you're knew to Net::UPS, and this manual doesn't seem to help, you're encouraged to read L<Net::UPS::Tutorial|Net::UPS::Tutorial> first.

=head1 METHODS

Following are the list and description of methods available through Net::UPS. Provided examples may also use other Net::UPS::* libraries and their methods. For the details of those please read their respective manuals. (See L<SEE ALSO|/"SEE ALSO">)

=over 4

=cut

use strict;
use Carp ('croak');
use XML::Simple;
use LWP::UserAgent;
use Net::UPS::ErrorHandler;
use Net::UPS::Rate;
use Net::UPS::Service;
use Net::UPS::Address;

@Net::UPS::ISA          = ( "Net::UPS::ErrorHandler" );
$Net::UPS::VERSION      = '0.01_01';
$Net::UPS::RATE_PROXY   = 'https://wwwcie.ups.com/ups.app/xml/Rate';
$Net::UPS::AV_PROXY     = 'https://wwwcie.ups.com/ups.app/xml/AV';
#$Net::UPS::AV_PROXY     = 'https://www.ups.com/ups.app/xml/AV';


sub PICKUP_TYPES () {
    return {
        DAILY_PICKUP            => '01',
        DAILY                   => '01',
        CUSTOMER_COUNTER        => '03',
        ONE_TIME_PICKUP         => '06',
        ONE_TIME                => '06',
        ON_CALL_AIR             => '07',
        SUGGESTED_RETAIL        => '11',
        SUGGESTED_RETAIL_RATES  => '11',
        LETTER_CENTER           => '19',
        AIR_SERVICE_CENTER      => '20'
    };
}

sub CUSTOMER_CLASSIFICATION () {
    return {
        WHOLESALE               => '01',
        OCCASIONAL              => '03',
        RETAIL                  => '04'
    };
}

=item new($userid, $password, $accesskey)

=item new($userid, $password, $accesskey, \%args)

Constructor method. Builds and returns Net::UPS instance. If an instance exists, C<new()> returns that instance.

C<$userid> and C<$password> are your login information to your UPS.com profile. C<$accesskey> is something you have to request from UPS.com to be able to use UPS Online Tools API.

C<\%args>, if present, are the global arguments you can pass to customize Net::UPS instance, and further calls to UPS.com. Available arguments are as follows

=over 4

=item pickup_type

Type of pickup to be assumed by subsequent rate() and shop_for_rate() calls. See L<PICKUP TYPES|PICKUP_TYPES> for the list of available pickup types.

=item ups_account_number

If you have a UPS account number, place it here.

=item customer_classification

Your Customer Classification. For details refer to UPS Online Tools API manual. In general, you'll get the lowest quote if your I<pickup_type> is I<DAILY> and your I<customer_classification> is I<WHOLESALE>. See L<CUSTOMER CLASSIFICATION|/"CUSTOMER CLASSIFICATION">

=back

=cut

my $ups = undef;
sub new {
    my $class = shift;
    croak "new(): usage error" if ref($class);

    if ( (@_ < 3) || (@_ > 4) ) {
        croak "new(): invalid number of arguments";
    }
    $ups = bless({
        __userid      => $_[0],
        __password    => $_[1],
        __access_key  => $_[2],
        __args        => $_[3] || {},
        __last_service=> undef
    }, $class);
    unless ( $ups->userid && $ups->password && $ups->access_key ) {
        croak "new(): usage error. Required arguments missing";
    }
    $ups->init();
    return $ups;
}


=item instance()

Returns an instance of Net::UPS object. Should be called after an instance is created previously by calling C<new()>. C<instance()> croaks if there is no object instance.

=cut


sub instance {
    return $ups if defined($ups);
    croak "instance(): no object instance found";
}

sub init    {}
sub rate_proxy   { $Net::UPS::RATE_PROXY}
sub av_proxy     { $Net::UPS::AV_PROXY  }


=item userid()

=item password()

=item access_key()

Return UserID, Password and AccessKey values respectively

=cut

sub userid  { return $_[0]->{__userid} }
sub password{ return $_[0]->{__password} }
sub access_key { return $_[0]->{__access_key} }

#=item dump()
#
#For debugging only. Dumps internal object data structure using Data::Dumper.
#
#=cut

sub dump    { return Dumper($_[0])  }

sub access_as_xml {
    my $self = shift;
    return XMLout({
        AccessRequest => {
            AccessLicenseNumber  => $self->access_key,
            Password            => $self->password,
            UserId              => $self->userid
        }
    }, NoAttr=>1, KeepRoot=>1, XMLDecl=>1);
}

sub transaction_reference {
    return {
        CustomerContext => "Net::UPS",
        XpciVersion     => '1.0001'
    };
}

=item rate($from, $to, $package)

=item rate($from, $to, \@packages)

=item rate($from, $to, \@packages, \%args

Returns one Net::UPS::Rate instance for every package requested. If there is only one package, returns a single reference to Net::UPS::Rate. If there are more then one packages passed, returns an arrayref of Net::UPS::Rate objects.

C<$from> and C<$to> can be either plain postal (zip) codes, or instances of Net::UPS::Address. In latter case, the only value required is C<postal_code()>.

C<$package> should be of Net::UPS::Package type and C<@packages> should be an array of Net::UPS::Package objects.

    $rate = $ups->rate(15146, 15241, $package);
    printf("Your cost is \$.2f\n", $rate->total_charges);

See L<Net::UPS::Package|Net::UPS::Package> for examples of building a package. See L<Net::UPS::Rate|Net::UPS::Rate> for examples of using C<$rate>.

C<\%args>, if present, can be used to customize C<rate()>ing process. Available arguments are:

=over 4

=item service

Specifies what kind of service to rate the package against. Default is I<GROUND>, which rates the package for I<UPS Ground>. See L<SERVICE TYPES|/"SERVICE TYPES"> for a list of available UPS services to choose from.

=back

=cut

sub rate {
    my $self = shift;
    my ($from, $to, $packages, $args) = @_;

    unless ( $from && $to && $packages ) {
        croak "rate(): usage error";
    }
    unless ( ref $from ) {
        $from = Net::UPS::Address->new(postal_code=>$from);
    }
    unless ( ref $to ) {
        $to   = Net::UPS::Address->new(postal_code=>$to);
    }
    unless ( ref $packages eq 'ARRAY' ) {
        $packages = [$packages];
    }
    $args                   ||= {};
    $args->{mode}             = "Rate";
    $args->{service}        ||= "GROUND";

    my $services = $self->request_rate($from, $to, $packages, $args);
    if ( @$packages == 1 ) {
        return $services->[0]->rates()->[0];
    }
    return $services->[0]->rates();
}


=item shop_for_rates($from, $to, $package)

=item shop_for_rates($from, $to, \@packages)

=item shop_for_rates($from, $to, \@packages, \%args)

The same as C<rate()>, except on success, returns an array reference to a list of all the available services for the addresses and the package. Each service is represented as an instance of Net::UPS::Service. Example:

    $services = $ups->shop_for_rates(15146, 15228, $package);
    while (my $service = shift @$services ) {
        printf("%-22s => \$.2f", $service->label, $service->total_charges);
        if ( my $days = $service->guaranteed_days ) {
            printf("(delivers in %d day%s)\n", $days, ($days > 1) ? "s" : "");
        } else {
            print "\n";
        }
    }

Above example returns all the service types available for shipping C<$package> from 15146 to 15228. Output may be similar to this:

    GROUND                 => $5.20
    3_DAY_SELECT           => $6.35  (delivers in 3 days)
    2ND_DAY_AIR            => $9.09  (delivers in 2 days)
    2ND_DAY_AIR_AM         => $9.96  (delivers in 2 days)
    NEXT_DAY_AIR_SAVER     => $15.33 (delivers in 1 day)
    NEXT_DAY_AIR           => $17.79 (delivers in 1 day)
    NEXT_DAY_AIR_EARLY_AM  => $49.00 (delivers in 1 day)

The above example won't change even if you passed multiple packages to be rated. Individual package rates can be accessed through C<rates()> method of Net::UPS::Service.

=cut

sub shop_for_rates {
    my $self = shift;
    my ($from, $to, $packages, $args) = @_;

    unless ( $from && $to && $packages ) {
        croak "shop_for_rates(): usage error";
    }
    unless ( ref $from ) {
        $from = Net::UPS::Address->new(postal_code=>$from);
    }
    unless ( ref $to ) {
        $to =  Net::UPS::Address->new(postal_code=>$to);
    }
    unless ( ref $packages eq 'ARRAY' ) {
        $packages = [$packages];
    }
    $args           ||= {};
    $args->{mode}     = "Shop";
    $args->{service}||= "GROUND";
    return $self->request_rate($from, $to, $packages, $args);
}



#
#=item request_rate($from, $to, $package)
#
#=item request_rate($from, $to, \@packages)
#
#=item request_rate($from, $to, \@packages, \%args)
#
#
#=cut

sub request_rate {
    my $self = shift;
    my ($from, $to, $packages, $args) = @_;

    unless ( $from && $to && $packages && $args) {
        croak "request_rate(): usage error";
    }
    unless (ref($from) && $from->isa("Net::UPS::Address")&&
            ref($to) && $to->isa("Net::UPS::Address") &&
            ref($packages) && (ref $packages eq 'ARRAY') &&
            ref($args) && (ref $args eq 'HASH')) {
        croak "request_rate(): usage error";
    }

    for (my $i=0; $i < @$packages; $i++ ) {
        $packages->[$i]->id( $i + 1 );
    }

    my %data = (
        RatingServiceSelectionRequest => {
            Request => {
                RequestAction   => 'Rate',
                RequestOption   =>  $args->{mode},
                TransactionReference => $self->transaction_reference,
            },
            PickupType  => {
                Code    => PICKUP_TYPES->{$self->{__args}->{pickup_type}||"ONE_TIME"}
            },
            Shipment    => {
                Service     => { Code   => Net::UPS::Service->new_from_label( $args->{service} )->code },
                Package     => [map { $_->as_hash()->{Package} } @$packages],
                Shipper     => $from->as_hash(),
                ShipTo      => $to->as_hash()
            }
    });
    if ( my $shipper_number = $self->{__args}->{ups_account_number} ) {
        $data{RatingServiceSelectionRequest}->{Shipment}->{Shipper}->{ShipperNumber} = $shipper_number;
    }
    if (my $classification_code = $self->{__args}->{customer_classification} ) {
        $data{RatingServiceSelectionRequest}->{CustomerClassification}->{Code} = CUSTOMER_CLASSIFICATION->{$classification_code};
    }
    my $xml         = $self->access_as_xml . XMLout(\%data, KeepRoot=>1, NoAttr=>1, KeyAttr=>[], XMLDecl=>1);
    my $response    = XMLin( $self->post( $self->rate_proxy, $xml ),
                                            KeepRoot => 0,
                                            NoAttr => 1,
                                            KeyAttr => [],
                                            ForceArray => ['RatedPackage', 'RatedShipment']);
    if ( my $error  =  $response->{Response}->{Error} ) {
        return $self->set_error( $error->{ErrorDescription} );
    }
    my @services;
    for (my $i=0; $i < @{$response->{RatedShipment}}; $i++ ) {
        my $ref = $response->{RatedShipment}->[$i] or die;
        my $service = Net::UPS::Service->new_from_code($ref->{Service}->{Code});
        $service->total_charges( $ref->{TotalCharges}->{MonetaryValue} );
        $service->guaranteed_days(ref($ref->{GuaranteedDaysToDelivery}) ?
                                                undef : $ref->{GuaranteedDaysToDelivery});
        $service->rated_packages( $packages );
        my @rates = ();
        for (my $j=0; $j < @{$ref->{RatedPackage}}; $j++ ) {
            push @rates, Net::UPS::Rate->new(
                billing_weight  => $ref->{RatedPackage}->[$j]->{BillingWeight}->{Weight},
                total_charges   => $ref->{RatedPackage}->[$j]->{TotalCharges}->{MonetaryValue},
                weight          => $ref->{Weight},
                rated_package   => $packages->[$j],
                service         => $service,
                from            => $from,
                to              => $to
            );
        }
        $service->rates(\@rates);
        push @services, $service;
        # remembering the last service:
        $self->{__last_service} = $service;
    }
    return \@services;
}


=item service()

Returns the last service used by the most recent call to C<rate()>.

=cut

sub service {
    return $_[0]->{__last_service};
}


#=item post($xml_content)
#
#Posts XML data to UPS.com's Online Tools  Server, and returns the content returned.
#
#=cut

sub post {
    my $self = shift;
    my ($url, $content) = @_;

    unless ( $url && $content ) {
        croak "post(): usage error";
    }

    my $user_agent  = LWP::UserAgent->new();
    my $request     = HTTP::Request->new('POST', $url);
    $request->content( $content );
    my $response    = $user_agent->request( $request );
    if ( $response->is_error ) {
        die $response->status_line();
    }
    return $response->content;
}


=item validate_address($address)

=item validate_address($address, \%args)

Validates a given address against UPS' U.S. Address Validation service. C<$address> can be one of the following:

=over 4

=item US Zip Code

=item Hash Reference

Keys of the hash should correspond to attributes of Net::UPS::Address

=item Net::UPS::Address class instance

=back

C<%args>, if present, contains arguments that effect validation results. As of this release the only supported argument is I<tolerance>, which defines threshold for address matches. I<threshold> is a floating point number between 0 and 1, inclusively. The higher the tolerance threshold, the more loose the address match is, thus more address suggestions are returned. Default I<tolerance> value is 0.05, which only returns very close matches.

    my $addresses = $ups->validate_address($address);
    unless ( defined $addresses ) {
        die $ups->errstr;
    }
    unless ( @$addresses ) {
        die "Address is not correct, nor are there any suggestions\n";
    }
    if ( $addresses->[0]->is_match ) {
        print "Address Matches Exactly!\n";
    } else {
        print "Your address didn't match exactly. Following are some valid suggestions\n";
        for (@$addresses ) {
            printf("%s, %s %s\n", $_->city, $_->state, $_->postal_code);
        }
    }

=cut

sub validate_address {
    my $self    = shift;
    my ($address, $args) = @_;

    unless ( defined $address ) {
        croak "verify_address(): usage error";
    }
    unless ( ref $address ) {
        $address = {postal_code => $address};
    }
    if ( ref $address eq 'HASH' ) {
        $address = Net::UPS::Address->new(%$address);
    }
    $args ||= {};
    unless ( defined $args->{tolerance} ) {
        $args->{tolerance} = 0.05;
    }
    unless ( ($args->{tolerance} >= 0) && ($args->{tolerance} <= 1) ) {
        croak "validate_address(): invalid tolerance threshold";
    }
    my %data = (
        AddressValidationRequest    => {
            Request => {
                RequestAction   => "AV",
                TransactionReference => $self->transaction_reference(),
            }
        }
    );
    if ( $address->city ) {
        $data{AddressValidationRequest}->{Address}->{City} = $address->city;
    }
    if ( $address->state ) {
        if ( length($address->state) != 2 ) {
            croak "StateProvinceCode has to be two letters long";
        }
        $data{AddressValidationRequest}->{Address}->{StateProvinceCode} = $address->state;
    }
    if ( $address->postal_code ) {
        $data{AddressValidationRequest}->{Address}->{PostalCode} = $address->postal_code;
    }
    my $xml = $self->access_as_xml . XMLout(\%data, KeepRoot=>1, NoAttr=>1, KeyAttr=>[], XMLDecl=>1);
    my $response = XMLin($self->post($self->av_proxy, $xml),
                                                KeepRoot=>0, NoAttr=>1,
                                                KeyAttr=>[], ForceArray=>["AddressValidationResult"]);
    if ( my $error = $response->{Response}->{Error} ) {
        return $self->set_error( $error->{ErrorDescription} );
    }
    my @addresses = ();
    for (my $i=0; $i < @{$response->{AddressValidationResult}}; $i++ ) {
        my $ref = $response->{AddressValidationResult}->[$i];
        next if $ref->{Quality} < (1 - $args->{tolerance});
        while ( $ref->{PostalCodeLowEnd} <= $ref->{PostalCodeHighEnd} ) {
            my $address = Net::UPS::Address->new(
                quality         => $ref->{Quality},
                postal_code     => $ref->{PostalCodeLowEnd},
                city            => $ref->{Address}->{City},
                state           => $ref->{Address}->{StateProvinceCode}
            );
            push @addresses, $address;
            $ref->{PostalCodeLowEnd}++;
        }
    }
    return \@addresses;
}





1;
__END__


=pod

=back

=head1 AUTHOR

Sherzod B. Ruzmetov E<lt>sherzodr@cpan.orgE<gt>, http://author.handalak.com/

=head1 COPYRIGHT

Copyright (C) 2005 Sherzod Ruzmetov. All rights reserved. This library is free software.
You can modify and/or distribute it under the same terms as Perl itself.

=head1 DISCLAIMER

THIS LIBRARY IS PROVIDED WITH USEFULNES IN MIND, BUT WITHOUT ANY GUARANTEE (NEITHER IMPLIED NOR EXPRESSED) OF ITS FITNES FOR A PARTICUALR PURPOSE. USE IT AT YOUR OWN RISK.

=head1 SEE ALSO

L<Net::UPS::Address|Net::UPS::Address>, L<Net::UPS::Rate>, L<Net::UPS::Service|Net::UPS::Service>, L<Net::UPS::Package|Net::UPS::Package>, L<Net::UPS::Tutorial|Net::UPS::Tutorial>

=head1 APPENDIXES

Some options need to be provided to UPS in the form of codes. These two-digit numbers are not ideal for mortals to work with. That's why Net::UPS decided to assign them symbolic names, I<constants>, if you wish.

=head2 SERVICE TYPES

Following is the table of SERVICE TYPE codes, and their symbolic names assigned by Net::UPS. One of these options can be passed as I<service> argument to C<rate()>, as in:

    $rates = $ups->rate($from, $to, $package, {service=>'2ND_DAY_AIR'});

    +------------------------+-----------+
    |    SYMBOLIC NAMES      | UPS CODES |
    +------------------------+-----------+
    | NEXT_DAY_AIR           |    01     |
    | 2ND_DAY_AIR            |    02     |
    | GROUND                 |    03     |
    | WORLDWIDE_EXPRESS      |    07     |
    | WORLDWIDE_EXPEDITED    |    08     |
    | STANDARD               |    11     |
    | 3_DAY_SELECT           |    12     |
    | NEXT_DAY_AIR_SAVER     |    13     |
    | NEXT_DAY_AIR_EARLY_AM  |    14     |
    | WORLDWIDE_EXPRESS_PLUS |    54     |
    | 2ND_DAY_AIR_AM'        |    59     |
    +------------------------+-----------+

=head2 CUSTOMER CLASSIFICATION

Following are the possible customer classifications. Can be passed to C<new()> as part of the argument list, as in:

    $ups = Net::UPS->new($userid, $password, $accesskey, {customer_classification=>'WHOLESALE'});

    +----------------+-----------+
    | SYMBOLIC NAMES | UPS CODES |
    +----------------+-----------+
    | WHOLESALE      |     01    |
    | OCCASIONAL     |     03    |
    | RETAIL         |     04    |
    +----------------+-----------+

=head2 PACKAGE CODES

Following are all valid packaging types that can be set through I<packaging_type> attribute of Net::UPS::Package, as in:

    $package = Net::UPS::Package->new(weight=>10, packaging_type=>'TUBE');

    +-----------------+-----------+
    | SYMBOLIC NAMES  | UPS CODES |
    +-----------------+-----------+
    | LETTER          |     01    |
    | PACKAGE         |     02    |
    | TUBE            |     03    |
    | UPS_PAK         |     04    |
    | UPS_EXPRESS_BOX |     21    |
    | UPS_25KG_BOX    |     24    |
    | UPS_10KG_BOX    |     25    |
    +-----------------+-----------+

=cut
