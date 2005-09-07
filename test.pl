
# $Id: test.pl,v 1.5 2005/09/07 00:09:13 sherzodr Exp $

use strict;
use diagnostics;
use Test::More ( 'no_plan' );

#unless ( $ENV{UPS_USERID} && $ENV{UPS_PASSWORD} && $ENV{UPS_ACCESSKEY} ) {
#    plan(skip_all=>"Environmental Variables are not set");
#    exit(0);
#}

use_ok("Net::UPS");
use_ok("Net::UPS::Address");
use_ok("Net::UPS::Package");
use_ok("Net::UPS::Service");
use_ok("Net::UPS::Rate");

