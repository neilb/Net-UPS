#!perl
use strict;
use warnings;
use Test::More;
use Net::UPS;
use File::Temp 'tempfile';

my ($fh,$filename) = tempfile();
print $fh <<'CONFIG';
UPSUserID user
UPSPassword pass
UPSAccessKey accesskey
UPSAVProxy http://my/AV
UPSRateProxy http://my/Rate
CONFIG
flush $fh;

for my $ups (
    Net::UPS->new('user','pass','accesskey',{
        av_proxy => 'http://my/AV',
        rate_proxy => 'http://my/Rate',
    }),
    Net::UPS->new($filename),
) {
    is($ups->userid,'user','user set');
    is($ups->password,'pass','password set');
    is($ups->av_proxy,'http://my/AV',
       'AV url set');
    is($ups->rate_proxy,'http://my/Rate',
       'Rate url set');
}

done_testing();
