package Net::UPS2;
use strict;
use warnings;
use Moo;
use XML::Simple;
use Types::Standard qw(Str Bool Object Dict Optional ArrayRef HashRef Undef);
use Type::Params qw(compile);
use Error::TypeTiny;
use Net::UPS2::Types qw(:types to_Service);
use Net::UPS2::Exception;
use Try::Tiny;
use List::AllUtils 'pairwise';
use HTTP::Request;
use Encode;
use namespace::autoclean;
use Net::UPS2::Rate;
use Net::UPS2::Address;
use Net::UPS2::Service;
use Net::UPS2::Response::Rate;
use Net::UPS2::Response::Address;
use 5.10.0;

# ABSTRACT: attempt to re-implement Net::UPS with modern insides

my %code_for_pickup_type = (
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
);
sub _pickup_types { return {%code_for_pickup_type} }

my %code_for_customer_classification = (
    WHOLESALE               => '01',
    OCCASIONAL              => '03',
    RETAIL                  => '04'
);
sub _customer_classification { return {%code_for_customer_classification} }

my %base_urls = (
    live => 'https://onlinetools.ups.com/ups.app/xml',
    test => 'https://wwwcie.ups.com/ups.app/xml',
);
sub _base_urls { return {%base_urls} }

has live_mode => (
    is => 'rw',
    isa => Bool,
    trigger => 1,
    default => sub { 0 },
);

has base_url => (
    is => 'lazy',
    isa => Str,
    clearer => '_clear_base_url',
);

sub _trigger_live_mode {
    my ($self) = @_;

    $self->_clear_base_url;
}
sub _build_base_url {
    my ($self) = @_;

    return $base_urls{$self->live_mode ? 'live' : 'test'};
}

has user_id => (
    is => 'ro',
    isa => Str,
    required => 1,
);
has password => (
    is => 'ro',
    isa => Str,
    required => 1,
);
has access_key => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has account_number => (
    is => 'ro',
    isa => Str,
);
has customer_classification => (
    is => 'rw',
    isa => CustomerClassification,
);

has pickup_type => (
    is => 'rw',
    isa => PickupType,
    default => sub { 'ONE_TIME' },
);

has cache => (
    is => 'ro',
    isa => Cache|Undef,
);
sub does_caching {
    my ($self) = @_;
    return defined $self->cache;
}

has user_agent => (
    is => 'lazy',
    isa => UserAgent,
);
sub _build_user_agent {
    require LWP::UserAgent;
    return LWP::UserAgent->new(
        env_proxy => 1,
    );
}

sub BUILDARGS {
    my ($class,@args) = @_;

    return _load_config_file($args[0])
        if @args==1 and not ref($args[0]);

    my $ret;
    if (@args==1 and ref($args[0]) eq 'HASH') {
        $ret = { %{$args[0]} };
    }
    else {
        $ret = { @args };
    }

    if (my $config_file = delete $ret->{config_file}) {
        $ret = {
            %{_load_config_file($config_file)},
            %$ret,
        };
    }

    if ($ret->{cache_life}) {
        require CHI;
        if (not $ret->{cache_root}) {
            require File::Spec;
            $ret->{cache_root} =
                File::Spec->catdir(File::Spec->tmpdir,'net_ups2'),
              }
        $ret->{cache} = CHI->new(
            driver => 'File',
            root_dir => $ret->{cache_root},
            depth => 5,
            expires_in => $ret->{cache_life} . ' min',
        );
    }

    return $ret;
}

sub _load_config_file {
    my ($file) = @_;
    require Config::Any;
    my $loaded = Config::Any->load_files({
        files => [$file],
        use_ext => 1,
        flatten_to_hash => 1,
    });
    my $config = $loaded->{$file};
    Net::UPS2::Exception::ConfigError->throw({
        file => $file,
    }) unless $config;
    return $config;
}

sub transaction_reference {
    return {
        CustomerContext => "Net::UPS",
        XpciVersion     => '1.0001'
    };
}

sub access_as_xml {
    my $self = shift;
    return XMLout({
        AccessRequest => {
            AccessLicenseNumber  => $self->access_key,
            Password            => $self->password,
            UserId              => $self->user_id,
        }
    }, NoAttr=>1, KeepRoot=>1, XMLDecl=>1);
}

sub request_rate {
    state $argcheck = compile(Object, Dict[
        from => Address,
        to => Address,
        packages => PackageList,
        limit_to => Optional[ArrayRef[Str]],
        exclude => Optional[ArrayRef[Str]],
        mode => Optional[RequestMode],
        service => Optional[Service],
    ]);
    my ($self,$args) = $argcheck->(@_);
    $args->{mode} ||= 'rate';
    $args->{service} ||= to_Service('GROUND');

    if ( $args->{exclude} && $args->{limit_to} ) {
        Error::TypeTiny::croak("You cannot use both 'limit_to' and 'exclude' at the same time");
    }

    my $packages = $args->{packages};

    unless (scalar(@$packages)) {
        Error::TypeTiny::croak("request_rate() was given an empty list of packages");
    }

    { my $pack_id=0; $_->id(++$pack_id) for @$packages }

    my $cache_key;
    if ($self->does_caching) {
        $cache_key = $self->generate_cache_key(
            'rate',
            [ $args->{from},$args->{to},@$packages, ],
            {
                mode => $args->{mode},
                service => $args->{service}->code,
                pickup_type => $self->pickup_type,
                customer_classification => $self->customer_classification,
            },
        );
        if (my $cached_services = $self->cache->get($cache_key)) {
            return $cached_services;
        }
    }

    my %request = (
        RatingServiceSelectionRequest => {
            Request => {
                RequestAction   => 'Rate',
                RequestOption   =>  $args->{mode},
                TransactionReference => $self->transaction_reference,
            },
            PickupType  => {
                Code    => $code_for_pickup_type{$self->pickup_type},
            },
            Shipment    => {
                Service     => { Code   => $args->{service}->code },
                Package     => [map { $_->as_hash() } @$packages],
                Shipper     => $args->{from}->as_hash(),
                ShipTo      => $args->{to}->as_hash(),
                ( $self->account_number ? (
                    Shipper => { ShipperNumber => $self->account_number }
                ) : () ),
            },
            ( $self->customer_classification ? (
                CustomerClassification => { Code => $code_for_customer_classification{$self->customer_classification} }
            ) : () ),
        }
    );

    my $response = $self->xml_request({
        data => \%request,
        url_suffix => '/Rate',
        XMLin => {
            ForceArray => [ 'RatedPackage', 'RatedShipment' ],
        },
    });

    # default to "all allowed"
    my %ok_labels = map { $_ => 1 } @{ServiceLabel->values};
    if ($args->{limit_to}) {
        # deny all, allow requested
        %ok_labels = map { $_ => 0 } @{ServiceLabel->values};
        $ok_labels{$_} = 1 for @{$args->{limit_to}};
    }
    elsif ($args->{exclude}) {
        # deny requested
        $ok_labels{$_} = 0 for @{$args->{exclude}};
    }

    my @services;
    for my $rated_shipment (@{$response->{RatedShipment}}) {
        my $code = $rated_shipment->{Service}{Code};
        my $label = Net::UPS2::Service::label_for_code($code);
        next if not $ok_labels{$label};

        push @services, my $service = Net::UPS2::Service->new({
            code => $code,
            label => $label,
            total_charges => $rated_shipment->{TotalCharges}{MonetaryValue},
            # TODO check this logic
            ( ref($rated_shipment->{GuaranteedDaysToDelivery})
                  ? ()
                  : ( guaranteed_days => $rated_shipment->{GuaranteedDaysToDelivery} ) ),
            rated_packages => $packages,
            # TODO check this pairwise
            rates => [ pairwise {
                Net::UPS2::Rate->new({
                    billing_weight  => $a->{BillingWeight}{Weight},
                    unit            => $a->{BillingWeight}{UnitOfMeasurement}{Code},
                    total_charges   => $a->{TotalCharges}{MonetaryValue},
                    total_charges_currency => $a->{TotalCharges}{CurrencyCode},
                    weight          => $a->{Weight},
                    rated_package   => $b,
                    from            => $args->{from},
                    to              => $args->{to},
                });
            } @{$rated_shipment->{RatedPackage}},@$packages ],
        });

        # fixup service-rate-service refs
        $_->_set_service($service) for @{$service->rates};
    }
    @services = sort { $a->total_charges <=> $b->total_charges } @services;

    my $ret = Net::UPS2::Response::Rate->new({
        services => \@services,
        ( $response->{Error} ? (warnings => $response->{Error}) : () ),
    });

    $self->cache->set($cache_key,$ret) if $self->does_caching;

    return $ret;
}

sub validate_address {
    state $argcheck = compile(
        Object,
        Address, Optional[Tolerance],
    );
    my ($self,$address,$tolerance) = $argcheck->(@_);

    $tolerance //= 0.05;

    my %data = (
        AddressValidationRequest => {
            Request => {
                RequestAction => "AV",
                TransactionReference => $self->transaction_reference(),
            },
            Address => {
                ( $address->city ? ( City => $address->city ) : () ),
                ( $address->state ? ( StateProvinceCode => $address->state) : () ),
                ( $address->postal_code ? ( PostalCode => $address->postal_code) : () ),
            },
        },
    );

    my $cache_key;
    if ($self->does_caching) {
        $cache_key = $self->generate_cache_key(
            'AV',
            [ $address ],
            { tolerance => $tolerance },
        );
        if (my $cached_services = $self->cache->get($cache_key)) {
            return $cached_services;
        }
    }

    my $response = $self->xml_request({
        data => \%data,
        url_suffix => '/AV',
        XMLin => {
            ForceArray => [ 'AddressValidationResult' ],
        },
    });

    my @addresses;
    for my $address (@{$response->{AddressValidationResult}}) {
        next if $address->{Quality} < (1 - $tolerance);
        for my $possible_postal_code ($address->{PostalCodeLowEnd} .. $address->{PostalCodeHighEnd}) {
            push @addresses, Net::UPS2::Address->new({
                quality         => $address->{Quality},
                postal_code     => $possible_postal_code,
                city            => $address->{Address}->{City},
                state           => $address->{Address}->{StateProvinceCode},
                country_code    => "US",
            });
        }
    }


    my $ret = Net::UPS2::Response::Address->new({
        addresses => \@addresses,
        ( $response->{Error} ? (warnings => $response->{Error}) : () ),
    });

    $self->cache->set($cache_key,$ret) if $self->does_caching;

    return $ret;
}

sub xml_request {
    state $argcheck = compile(
        Object,
        Dict[
            data => HashRef,
            url_suffix => Str,
            XMLout => Optional[HashRef],
            XMLin => Optional[HashRef],
        ],
    );
    my ($self, $args) = $argcheck->(@_);

    # default XML::Simple args
    my $xmlargs = {
        NoAttr     => 1,
        KeyAttr    => [],
    };

    my $request =
        $self->access_as_xml .
            XMLout(
                $args->{data},
                %{ $xmlargs },
                XMLDecl     => 1,
                KeepRoot    => 1,
                %{ $args->{XMLout}||{} },
            );

    my $response_string = $self->post( $args->{url_suffix}, $request );

    my $response = XMLin(
        $response_string,
        %{ $xmlargs },
        %{ $args->{XMLin} },
    );

    if ($response->{Response}{ResponseStatusCode}==0) {
        Net::UPS2::Exception::UPSError->throw({
            error => $response->{Response}{Error}
        });
    }

    return $response;
}

sub post {
    state $argcheck = compile( Object, Str, Str );
    my ($self, $url_suffix, $body) = $argcheck->(@_);

    my $url = $self->base_url . $url_suffix;
    my $request = HTTP::Request->new(
        POST => $url,
        [], encode('utf-8',$body),
    );
    my $response = $self->user_agent->request($request);

    if ($response->is_error) {
        Net::UPS2::Exception::HTTPError->throw({
            request=>$request,
            response=>$response,
        });
    }

    return $response->decoded_content(default_charset=>'utf-8',raise_error=>1);
}

sub generate_cache_key {
    state $argcheck = compile(Object, Str, ArrayRef[Cacheable],Optional[HashRef]);
    my ($self,$kind,$things,$args) = $argcheck->(@_);

    return join ':',
        $kind,
        ( map { $_->cache_id } @$things ),
        ( map {
            sprintf '%s:%s',
                $_,
                ( defined($args->{$_}) ? '"'.$args->{$_}.'"' : 'undef' )
            } sort keys %{$args || {}}
        );
}

1;
