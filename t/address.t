#!perl
use strict;
use warnings;
use 5.10.0;
use Test::Most;
use Net::UPS2;
use Net::UPS2::Address;
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

my $address = Net::UPS2::Address->new({
    city => 'East Lansing',
    postal_code => '48823',
    state => 'MI',
    country_code => 'US',
    is_residential => 1,
});

my $addresses = $ups->validate_address($address);

cmp_deeply($addresses,
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

done_testing();

