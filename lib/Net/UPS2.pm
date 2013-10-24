package Net::UPS2;
use strict;
use warnings;
use Moo;
use XML::Simple;
use Types::Standard qw(Str Bool Object Dict Optional ArrayRef HashRef);
use Type::Params qw(compile);
use Net::UPS2::Types ':types';
use Net::UPS2::Exception;
use Try::Tiny;
use List::AllUtils 'zip';
use HTTP::Request;
use Encode;
use namespace::autoclean;
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

my %code_for_customer_classification = (
    WHOLESALE               => '01',
    OCCASIONAL              => '03',
    RETAIL                  => '04'
);

has live_mode => (
    is => 'rw',
    isa => Bool,
    trigger => 1,
);

has base_url => (
    is => 'ro',
    isa => Str,
    lazy => 1,
    clearer => '_clear_base_url',
);

sub _trigger_live_mode {
    my ($self) = @_;

    $self->_clear_base_url;
}
sub _build_base_url {
    my ($self) = @_;

    return $self->live_mode
        ? 'https://onlinetools.ups.com/ups.app/xml'
        : 'https://wwwcie.ups.com/ups.app/xml';
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
    is => 'ro',
    isa => CustomerClassification,
);

has pickup_type => (
    is => 'rw',
    isa => PickupType,
    default => sub { 'ONE_TIME' },
);


has cache => (
    is => 'ro',
    isa => Cache,
    lazy => 1,
);
sub _build_cache {
    require CHI;
    require File::Spec;
    return CHI->new(
        driver => 'File',
        root_dir => File::Spec->catdir(File::Spec->tmpdir,'net_ups2'),
        depth => 5,
    );
}

has user_agent => (
    is => 'ro',
    isa => UserAgent,
    lazy => 1,
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
    die "Bad config file $file" unless $config;
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
        mode => RequestMode,
        service => Service,
    ]);
    my ($self,$args) = $argcheck->(@_);

    my $packages = $args->{packages};
    { my $pack_id=0; $_->id(++$pack_id) for @$packages }

    # TODO here goes caching

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
    });

    # default to "all allowed"
    my %ok_labels = map { $_ => 1 } ServiceCode->values;
    if ($args->{limit_to}) {
        # deny all, allow requested
        %ok_labels = map { $_ => 0 } ServiceCode->values;
        $ok_labels{$_} = 1 for @{$args->{limit_to}};
    }
    elsif ($args->{exclude}) {
        # deny requested
        $ok_labels{$_} = 0 for @{$args->{exclude}};
    }

    my @services;
    for my $rated_shipment (@{$response->{RatedShipment}}) {
        my $code = $rated_shipment->{Service}->{Code};
        my $label = Net::UPS2::Service::label_for_code($code);
        next if not $ok_labels{$label};

        push @services, Net::UPS2::Service->new(
            code => $code,
            label => $label,
            total_charges => $rated_shipment->{TotalCharges}->{MonetaryValue},
            # TODO check this logic
            guaranteed_days => ( ref($rated_shipment->{GuaranteedDaysToDelivery})
                                     ? undef
                                     : $rated_shipment->{GuaranteedDaysToDelivery} ),
            rated_packages => $packages,
            # TODO check this pairwise
            rates => [ pairwise {
                Net::UPS::Rate->new({
                    billing_weight  => $a->{BillingWeight}->{Weight},
                    total_charges   => $a->{TotalCharges}->{MonetaryValue},
                    weight          => $rated_shipment->{Weight},
                    rated_package   => $b,
                    service         => $args->{service},
                    from            => $args->{from},
                    to              => $args->{to},
                });
            } zip @{$rated_shipment->{RatedPackage}},@$packages ],
        );
    }

    # TODO caching goes here
    return \@services;
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

    # default XML::Simple args; TODO check these, request_rate has them different
    my $xmlargs = {
        KeepRoot   => 0,
        NoAttr     => 1,
        KeyAttr    => [],
    };

    my $request =
        $self->access_as_xml .
            XMLout(
                $args->{data},
                %{ $xmlargs },
                XMLDecl     => 0,
                KeepRoot    => 1,
                %{ $args->{XMLout}||{} },
            );

    my $response_string = $self->post( $args->{url_suffix}, $request );

    my $response = XMLin(
        $response_string,
        %{ $xmlargs },
        %{ $args->{XMLin} },
    );

    if (my $error = $response->{Response}{Error}) {
        Net::UPS2::Exception::UPSError->throw({error=>$error});
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

1;
