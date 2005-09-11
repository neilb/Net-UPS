
# $Id: test.pl,v 1.6 2005/09/11 05:05:25 sherzodr Exp $

use strict;
use diagnostics;
use Test::More ( 'no_plan' );
use Config::Simple;
use File::Spec;

my $upsrc = File::Spec->catfile($ENV{HOME}, '.upsrc');
unless ( -r $upsrc ) {
    plan(skip_all=>"~/.upsrc is not found");
    exit(0);
}

my %config = ();
Config::Simple->import_from($upsrc, \%config);

unless ( $config{UserId} && $config{Password} && $config{AccessKey} ) {
    plan(skip_all=>"Access information are not set");
    exit(0);
}

use_ok("Net::UPS");
use_ok("Net::UPS::Address");
use_ok("Net::UPS::Package");
use_ok("Net::UPS::Service");
use_ok("Net::UPS::Rate");

my $ups = Net::UPS->new($config{UserId}, $config{Password}, $config{AccessKey});

if ( eval "require Cache::File" ) {
    $ups = Net::UPS->new($config{UserId}, $config{Password}, $config{AccessKey}, {
        cache_life => 30})
}

ok($ups, "$ups");

my $package = Net::UPS::Package->new(length=>'40', width=>'30', height=>'3', weight=>'3');
ok(defined($package) && ($package->length == 40) && ($package->width==30) && 
    ($package->height==3) && ($package->weight==3), "Package Data are consistent");

ok($package->cache_id eq 'PACKAGE:40:30:3:3', "Package Cache ID is " . $package->cache_id);

my $from = Net::UPS::Address->new(postal_code=>15241);
ok(defined($from) && ($from->postal_code==15241), "Origination address data are consistent");

my $to = Net::UPS::Address->new(postal_code=>15146);
ok(defined($to) && ($to->postal_code==15146), "Destination address data are consistent");

my $rate = $ups->rate($from, $to, $package);
ok(defined($rate) && ref($rate) && $rate->isa("Net::UPS::Rate") && $rate->can("total_charges"), 
            "rate() returns Net::UPS::Rate instance");
ok($rate->total_charges, "total_charges: " . sprintf("\$%.2f", $rate->total_charges));

my $services = $ups->shop_for_rates(15146, 48823, $package, {limit_to=>['GROUND', 'NEXT_DAY_AIR']});

print "\n";
while (my $service = shift @$services ) {
    printf ("\t%21s => \$%.2f\n", $service->label, $service->total_charges);
}
print "\n";

for my $service_type ( 'GROUND', '3_DAY_SELECT', '2ND_DAY_AIR', '2ND_DAY_AIR_AM', 'NEXT_DAY_AIR_SAVER', 'NEXT_DAY_AIR', 'NEXT_DAY_AIR_EARLY_AM') {
    $rate = $ups->rate(15146, 48823, $package, {service=>$service_type});
    ok($rate->total_charges, sprintf("%s: \$%.2f", $service_type, $rate->total_charges));
}
