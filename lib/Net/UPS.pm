package Net::UPS;
use strict;
use warnings;
use Net::UPS::ErrorHandler;
use Net::UPS::Rate;
use Net::UPS::Service;
use Net::UPS::Address;
use Net::UPS::Package;
use Net::UPS2;
use Net::UPS2::Types ':to';
use Try::Tiny;
use Carp qw(croak confess);

@Net::UPS::ISA          = ( "Net::UPS::ErrorHandler" );
$Net::UPS::LIVE         = 0;

sub RATE_TEST_PROXY () { Net::UPS2::_base_urls->{test}.'/Rate' }
sub RATE_LIVE_PROXY () { Net::UPS2::_base_urls->{live}.'/Rate' }
sub AV_TEST_PROXY   () { Net::UPS2::_base_urls->{test}.'/AV' }
sub AV_LIVE_PROXY   () { Net::UPS2::_base_urls->{live}.'/AV' }

sub PICKUP_TYPES () { Net::UPS2::_pickup_types }

sub CUSTOMER_CLASSIFICATION () { Net::UPS2::_customer_classification }

sub import {
    my $class = shift;
    @_ or return;
    if ( @_ % 2 ) {
        croak "import(): argument list has tobe in key=>value format";
    }
    my $args = { @_ };
    $Net::UPS::LIVE = $args->{live} || 0;
}

sub live {
    my $class = shift;
    unless ( @_ ) {
        croak "$class->live(): usage error";
    }
    $Net::UPS::LIVE = shift;
}

my $ups = undef;
sub new {
    my $class = shift;
    croak "new(): usage error" if ref($class);

    unless ( (@_ >= 1) || (@_ <= 4) ) {
        croak "new(): invalid number of arguments";
    }
    my $args = {
        user_id => $_[0] || undef,
        password => $_[1] || undef,
        access_key  => $_[2] || undef,
        %{ $_[3] || {} },
    };

    if ( @_ < 3 ) {
        my $args_from_file = $class->_read_args_from_file(@_) or return undef;
        $args = { %$args, %$args_from_file };
    }

    unless ( $args->{user_id} && $args->{password} && $args->{access_key} ) {
        croak "new(): usage error. Required arguments missing";
    }

    if ($args->{av_proxy} or $args->{rate_proxy}) {
        my %base;my %ext = (av=>'/AV',rate=>'/Rate');
        for my $serv (qw(av rate)) {
            if ($args->{"${serv}_proxy"}) {
                my $ext = $ext{$serv};
                ($base{$serv}) =
                    $args->{"${serv}_proxy"} =~ m{^(http.*?)\Q$ext\E$};
                if (not $base{$serv}) {
                    croak "bad $serv override url: ".$args->{"${serv}_proxy"};
                }
            }
        }
        if (values %base == 1) {
            croak "you must override both AV and Rate proxies";
        }
        if ($base{av} ne $base{rate}) {
            croak "overridden AV and Rate proxies must refer to the same server";
        }
        $args->{base_url} = $base{av};
    }

    $ups = bless {
        delegate => Net::UPS2->new($args),
        last_service => undef,
    }, $class;

    return $ups;
}

sub instance {
    return $ups if defined($ups);
    croak "instance(): no object instance found";
}

my %field_map = (
    UserID => 'user_id',
    Password => 'password',
    AccessKey => 'access_key',
    CustomerClassification => 'customer_classification',
    AccountNumber => 'account_number',
    CacheLife => 'cache_life',
    CacheRoot => 'cache_root',
    RateProxy => 'rate_proxy',
    AVProxy => 'av_proxy',
);
sub _read_args_from_file {
    my ($self,$path) = @_;

    unless ( defined $path ) {
        croak "_read_args_from_file(): required arguments are missing";
    }

    require IO::File;
    my $fh = IO::File->new($path, '<') or return $self->set_error("couldn't open $path: $!");
    my %config = ();
    while (local $_ = $fh->getline) {
        next if /^\s*\#/;
        next if /^\n/;
        next unless /^UPS/;
        chomp();
        my ($key, $value) = m/^\s*UPS(\w+)\s+(\S+)$/;
        $config{ $key } = $value;
    }
    unless ( $config{UserID} && $config{Password} && $config{AccessKey} ) {
        return $self->set_error( "_read_args_from_file(): required arguments are missing" );
    }

    my %ret;
    for my $src (keys %field_map) {
        next unless exists $config{$src};
        my $dst = $field_map{$src};

        $ret{$dst} = $config{$src};
    }

    return \%ret;
}

sub init        { confess 'Net::UPS::init is no longer supported' }
sub rate_proxy  { return $_[0]->{delegate}->base_url . '/Rate' }
sub av_proxy    { return $_[0]->{delegate}->base_url . '/AV' }
sub cache_life  { confess 'altering Net::UPS::cache_life is no longer supported' }
sub cache_root  { confess 'altering Net::UPS::cache_root is no longer supported' }
sub userid      { return $_[0]->{delegate}->user_id }
sub password    { return $_[0]->{delegate}->password }
sub access_key  { return $_[0]->{delegate}->access_key }
sub account_number { return $_[0]->{delegate}->account_number }
sub customer_classification { return $_[0]->{delegate}->customer_classification }
sub dump        { confess 'Net::UPS::dump is no longer supported' }

sub access_as_xml { return $_[0]->{delegate}->access_as_xml }

sub transaction_reference { return $_[0]->{delegate}->transaction_reference }

sub rate {
    my $self = shift;
    my ($from, $to, $packages, $args) = @_;
    croak "rate(): usage error" unless ($from && $to && $packages);

    my $services = $self->request_rate($from, $to, $packages, $args || {});
    return if !defined $services;

    if ( ref($packages) ne 'ARRAY' or @$packages == 1 ) {
        return $services->[0]->rates()->[0];
    }

    return $services->[0]->rates();
}

sub shop_for_rates {
    my $self = shift;
    my ($from, $to, $packages, $args) = @_;

    unless ( $from && $to && $packages ) {
        croak "shop_for_rates(): usage error";
    }

    $args->{mode} = "shop";
    my $services = $self->request_rate($from, $to, $packages, $args || {});
    return undef if !defined $services;

    return $services;
}

sub request_rate {
    my $self = shift;
    my ($from, $to, $packages, $args) = @_;

    croak "request_rate(): usage error" unless ($from && $to && $packages && $args);
    unless (scalar(@$packages)) {
        return $self->set_error( "request_rate() was given an empty list of packages!" );
    }

    my $error;
    my $response = try {
        $self->{delegate}->request_rate({
            from => $from,
            to => $to,
            packages => $packages,
            %$args,
        });
    }
    catch {
        warn "Caught: $_";
        if ($_->can('error')) {
            $error = $_->error->{ErrorDescription};
        }
        else {
            $error = "$_";
        }
    };
    return $self->set_error($error) if $error;

    my @services = map { to_OldService($_) } @{$response->services};

    $self->{last_service} = $services[-1];

    return \@services;
}

sub service { return $_[0]->{last_service} }

sub validate_address {
    my $self    = shift;
    my ($address, $args) = @_;

    croak "verify_address(): usage error" unless defined($address);

    my $error;
    my $response = try {
        $self->{delegate}->validate_address(
            $address,
            ( defined $args->{tolerance} ? $args->{tolerance} : () ),
        );
    }
    catch {
        if ($_->can('error')) {
            $error = $_->error->{ErrorDescription};
        }
        else {
            $error = "$_";
        }
    };
    return $self->set_error($error) if $error;

    my @addresses = map { to_OldAddress($_) } @{$response->addresses};

    return \@addresses;
}

1;
__END__

=head1 NAME

Net::UPS - Implementation of UPS Online Tools API in Perl

=head1 SYNOPSIS

    use Net::UPS;
    $ups = Net::UPS->new($userid, $password, $accesskey);
    $rate = $ups->rate($from_zip, $to_zip, $package);
    printf("Shipping this package $from_zip => $to_zip will cost you \$.2f\n", $rate->total_charges);

=head1 DESCRIPTION

Net::UPS implements UPS' Online Tools API in Perl. In a nutshell, Net::UPS knows how to retrieve rates and service information for shipping packages using UPS, as well as for validating U.S. addresses.

This manual is optimized to be used as a quick reference. If you're knew to Net::UPS, and this manual doesn't seem to help, you're encouraged to read L<Net::UPS::Tutorial|Net::UPS::Tutorial> first.

=head1 METHODS

Following are the list and description of methods available through Net::UPS. Provided examples may also use other Net::UPS::* libraries and their methods. For the details of those please read their respective manuals. (See L<SEE ALSO|/"SEE ALSO">)

=over 4

=item live ($bool)

By default, all the API calls in Net::UPS are directed to UPS.com's test servers. This is necessary in testing your integration interface, and not to exhaust UPS.com live servers.

Once you want to go live, L<live()|/"live"> class method needs to be called with a true argument to indicate you want to switch to the UPS.com's live interface. It is recommended that you call live() before creating a Net::UPS instance by calling L<new()|/"new">, like so:

    use Net::UPS;
    Net::UPS->live(1);
    $ups = Net::UPS->new($userid, $password, $accesskey);

=item new($userid, $password, $accesskey)

=item new($userid, $password, $accesskey, \%args)

=item new($config_file)

=item new($config_file, \%args)

Constructor method. Builds and returns Net::UPS instance. If an instance exists, C<new()> returns that instance.

C<$userid> and C<$password> are your login information to your UPS.com profile. C<$accesskey> is something you have to request from UPS.com to be able to use UPS Online Tools API.

C<\%args>, if present, are the global arguments you can pass to customize Net::UPS instance, and further calls to UPS.com. Available arguments are as follows:

=over 4

=item pickup_type

Type of pickup to be assumed by subsequent L<rate()|/"rate"> and L<shop_for_rates()|/"shop_for_rates"> calls. See L<PICKUP TYPES|PICKUP_TYPES> for the list of available pickup types.

=item ups_account_number

If you have a UPS account number, place it here.

=item customer_classification

Your Customer Classification. For details refer to UPS Online Tools API manual. In general, you'll get the lowest quote if your I<pickup_type> is I<DAILY> and your I<customer_classification> is I<WHOLESALE>. See L<CUSTOMER CLASSIFICATION|/"CUSTOMER CLASSIFICATION">

=item cache_life

Enables caching, as well as defines the life of cache in minutes.

=item cache_root

File-system location of a cache data. Return value of L<tmpdir()|File::Spec/tempdir> is used as default location.

=item av_proxy

The URL to use to access the AV service. If you set this one, the
L</live> setting will be ignored, and this URL always used.

=item rate_proxy

The URL to use to access the Rate service. If you set this one, the
L</live> setting will be ignored, and this URL always used.

=back

All the C<%args> can also be defined in the F<$config_file>. C<%args> can be used to overwrite the default arguments. See L<CONFIGURATION FILE|/"CONFIGURATION FILE">

=item instance ()

Returns an instance of Net::UPS object. Should be called after an instance is created previously by calling C<new()>. C<instance()> croaks if there is no object instance.

=item userid ()

=item password ()

=item access_key ()

Return UserID, Password and AccessKey values respectively

=item rate ($from, $to, $package)

=item rate ($from, $to, \@packages)

=item rate ($from, $to, \@packages, \%args)

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

=item shop_for_rates ($from, $to, $package)

=item shop_for_rates ($from, $to, \@packages)

=item shop_for_rates ($from, $to, \@packages, \%args)

The same as L<rate()|/"rate">, except on success, returns a reference to a list of available services. Each service is represented as an instance of L<Net::UPS::Service|Net::UPS::Service> class. Output is sorted by L<total_charges()|Net::UPS::Service/"total_charges"> in ascending order. Example:

    $services = $ups->shop_for_rates(15228, 15241, $package);
    while (my $service = shift @$services ) {
        printf("%-22s => \$.2f", $service->label, $service->total_charges);
        if ( my $days = $service->guaranteed_days ) {
            printf("(delivers in %d day%s)\n", $days, ($days > 1) ? "s" : "");
        } else {
            print "\n";
        }
    }

Above example returns all the service types available for shipping C<$package> from 15228 to 15241. Output may be similar to this:

    GROUND                 => $5.20
    3_DAY_SELECT           => $6.35  (delivers in 3 days)
    2ND_DAY_AIR            => $9.09  (delivers in 2 days)
    2ND_DAY_AIR_AM         => $9.96  (delivers in 2 days)
    NEXT_DAY_AIR_SAVER     => $15.33 (delivers in 1 day)
    NEXT_DAY_AIR           => $17.79 (delivers in 1 day)
    NEXT_DAY_AIR_EARLY_AM  => $49.00 (delivers in 1 day)

The above example won't change even if you passed multiple packages to be rated. Individual package rates can be accessed through L<rates()|Net::UPS::Service/"rates"> method of L<Net::UPS::Service|Net::UPS::Service>.

C<\%args>, if present, can be used to customize the rating process and/or the return value. Currently supported arguments are:

=over 4

=item limit_to

Tells Net::UPS which service types the result should be limited to. I<limit_to> should always refer to an array of services. For example:

    $services = $ups->shop_for_rates($from, $to, $package, {
                            limit_to=>['GROUND', '2ND_DAY_AIR', 'NEXT_DAY_AIR']
    });

This example returns rates for the selected service types only. All other service types will be ignored. Note, that it doesnt' guarantee all the requested service types will be available in the return value of C<shop_for_rates()>. It only returns the services (from the list provided) that are available between the two addresses for the given package(s).

=item exclude

The list provided in I<exclude> will be excluded from the list of available services. For example, assume you don't want rates for 'NEXT_DAY_AIR_SAVER', '2ND_DAY_AIR_AM' and 'NEXT_DAY_AIR_EARLY_AM' returned:

    $service = $ups->from_for_rates($from, $to, $package, {
                    exclude => ['NEXT_DAY_AIR_SAVER', '2ND_DAY_AIR_AM', 'NEXT_DAY_AIR_EARLY_AM']});

Note that excluding services may even generate an empty service list, because for some location excluded services might be the only services available. You better contact your UPS representative for consultation. As of this writing I haven't done that yet.

=back

=item service ()

Returns the last service used by the most recent call to C<rate()>.

=item validate_address ($address)

=item validate_address ($address, \%args)

Validates a given address against UPS' U.S. Address Validation service. C<$address> can be one of the following:

=over 4

=item *

US Zip Code

=item *

Hash Reference - keys of the hash should correspond to attributes of Net::UPS::Address

=item *

Net::UPS::Address class instance

=back

C<%args>, if present, contains arguments that effect validation results. As of this release the only supported argument is I<tolerance>, which defines threshold for address matches. I<tolerance> is a floating point number between 0 and 1, inclusively. The higher the tolerance threshold, the more loose the address match is, thus more address suggestions are returned. Default I<tolerance> value is 0.05, which only returns very close matches.

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

=pod

=back

=head1 BUGS AND KNOWN ISSUES

No bugs are known of as of this release. If you think you found a bug, document it at http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-UPS. It's more likely to get noticed in there than in my busy inbox.

=head1 TODO

There are still a lot of features UPS.com offers in its Online Tools API that Net::UPS doesn't handle. This is the list of features that need to be supported before Net::UPS can claim full compliance.

=head2 PACKAGE OPTIONS

Following features needs to be supported by Net::UPS::Package class to define additional package options:

=over 4

=item COD

=item Delivery Confirmation

=item Insurance

=item Additional Handling flag

=back

=head2 SERVICE OPTIONS

Following featureds need to be supported by Net::UPS::Service as well as in form of arguments to rate() and shop_for_rates() methods:

=over 4

=item Saturday Pickup

=item Saturday Delivery

=item COD Service request

=item Handling Charge

=back

=head1 AUTHOR

Sherzod B. Ruzmetov E<lt>sherzodr@cpan.orgE<gt>, http://author.handalak.com/

=head2 CREDITS

Thanks to Christian - E<lt>cpan [AT] pickledbrain.comE<gt> for locating and fixing a bug in Net::UPS::Package::is_oversized(). See the source for details.

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

=head2 CONFIGURATION FILE

Net::UPS object can also be instantiated using a configuration file. Example:

    $ups = Net::UPS->new("/home/sherzodr/.upsrc");
    # or
    $ups = Net::UPS->new("/home/sherzodr/.upsrc", \%args);

All the directives in the configuration file intended for use by Net::UPS will be prefixed with I<UPS>. All other directives that Net::UPS does not recognize will be conveniently ignored. Configuration file uses the following format:

    DirectiveName  DirectiveValue

Where C<DirectiveName> is one of the keywords documented below.

=head3 SUPPORTED DIRECTIVES

=over 4

=item UPSAccessKey

AccessKey as acquired from UPS.com Online Tools web site. Required.

=item UPSUserID

Online login id for the account. Required.

=item UPSPassword

Online password for the account. Required.

=item UPSCacheLife

To Turn caching on. Value of the directive also defines life-time for the cache.

=item UPSCacheRoot

Place to store cache files in. Setting this directive does not automatically turn caching on. UPSCacheLife needs to be set for this directive to be effective. UPSCacheRoot will defautlt o your system's temporary folder if it's missing.

=item UPSLive

Setting this directive to any true value will make Net::UPS to initiate calls to UPS.com's live servers. Without this directive Net::UPS always operates under test mode.

=item UPSPickupType

=item UPSAccountNumber

=item UPSCustomerClassification


=back

=cut
