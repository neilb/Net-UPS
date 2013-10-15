#!perl
use strict;
use warnings;
use Test::More;
use Net::UPS;

my $ups = Net::UPS->new('user','pass','accesskey',{
    av_proxy => 'http://my/av',
    rate_proxy => 'http://my/rate',
});

is($ups->av_proxy,'http://my/av',
   'AV url set');
is($ups->rate_proxy,'http://my/rate',
   'Rate url set');

done_testing();
