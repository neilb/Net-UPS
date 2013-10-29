#!perl
use strict;
use warnings;
use 5.10.0;
use lib 't/lib';
use Test::Most;
use Net::UPS2;
use Net::UPS2::Address;
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

my $address = Net::UPS2::Address->new({
    city => 'East Lansing',
    postal_code => '48823',
    state => 'MI',
    country_code => 'US',
    is_residential => 1,
});

my $addresses = $ups->validate_address($address);

cmp_deeply($addresses->addresses,
           array_each(
               all(
                   isa('Net::UPS2::Address'),
                   methods(
                       quality => num(1.0,0),
                       is_residential => undef,
                       is_exact_match => bool(1),
                       is_poor_match => bool(0),
                       is_close_match => bool(1),
                       is_very_close_match => bool(1),
                   ),
               ),
           ),
           'address validated',
) or p $addresses;
cmp_deeply(\@calls,
           [[ $ups,'/AV',ignore() ]],
           'one call to the service');

my $addresses2 = $ups->validate_address($address);
cmp_deeply($addresses2,$addresses,'the same answer');
cmp_deeply(\@calls,
           [[ $ups,'/AV',ignore() ]],
           'still only one call to the service');

$ups = Net::UPS2->new({
    config_file => $upsrc,
    cache => undef, # disable caching
});
my $addresses3 = $ups->validate_address($address);
cmp_deeply($addresses3,$addresses,'the same answer');
cmp_deeply(\@calls,
           [[ ignore(),'/AV',ignore() ],
            [ $ups,'/AV',ignore() ]],
           'two calls to the service');

done_testing();

