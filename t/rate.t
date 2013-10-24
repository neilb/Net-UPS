#!perl
use strict;
use warnings;
use 5.10.0;
use Test::Most;
use Net::UPS2;
use Net::UPS2::Package;
use File::Spec;
use Try::Tiny;
use Data::Printer;

my $upsrc = File::Spec->catfile($ENV{HOME}, '.upsrc.conf');
my $ups = try {
    Net::UPS2->new($upsrc);
}
catch {
    plan(skip_all=>$_);
    exit(0);
};

my $package =
    Net::UPS2::Package->new({
        length => 34,
        width => 24,
        height => 1.5,
        weight => 1,
        measurement_system => 'english',
    });

ok($package, 'packages can be created');

my $services = $ups->request_rate({
    from => 15241,
    to => 48823,
    packages => $package,
    mode => 'rate',
    service => 'GROUND',
});

ok($services && @$services,'got answer');

done_testing();
