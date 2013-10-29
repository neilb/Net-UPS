#!perl
use strict;
use warnings;
use 5.10.0;
use lib 't/lib';
use Test::Most;
use Net::UPS2;
use Net::UPS2::Package;
use File::Spec;
use Try::Tiny;
use Sub::Override;
use Data::Printer;
use Test::Net::UPS2::TestCache;

my $orig_post = \&Net::UPS2::post;
my @calls;
my $new_post = Sub::Override->new(
    'Net::UPS2::post',
    sub {
        note "my post";
        push @calls,[@_];
        $orig_post->(@_);
    }
);

my $cache = Test::Net::UPS2::TestCache->new();
my $upsrc = File::Spec->catfile($ENV{HOME}, '.upsrc.conf');
my $ups = try {
    Net::UPS2->new({
        config_file => $upsrc,
        cache => $cache,
    });
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

my $argpack = {
    from => 15241,
    to => 48823,
    packages => $package,
    mode => 'rate',
    service => 'GROUND',
};

my $services = $ups->request_rate($argpack);
ok($services && @{$services->services},'got answer');
cmp_deeply(\@calls,
           [[ $ups,'/Rate',ignore() ]],
           'one call to the service');

my $services2 = $ups->request_rate($argpack);
ok($services2 && @{$services2->services},'got answer again');
cmp_deeply($services2,$services,'the same answer');
cmp_deeply(\@calls,
           [[ $ups,'/Rate',ignore() ]],
           'still only one call to the service');

done_testing();
