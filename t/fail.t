#!perl
use strict;
use Data::Printer;
use File::Spec;
use Net::UPS;

my $upsrc = File::Spec->catfile($ENV{HOME}, ".upsrc");
my $ups = Net::UPS->new($upsrc);
my $address = Net::UPS::Address->new();
$address->city('DDDDDDDDDDDDDDDDDDDDDDD');
$address->postal_code('GGGGGGGGGGGGGGGGGGGGGGG');
$address->state('CA');
$address->country_code('US');

my $addresses = $address->validate();
p $addresses;
