package Net::UPS2::Types;
use strict;
use warnings;
use Type::Library
    -base,
    -declare => qw( PickupType CustomerClassification
                    Cache
                    Address Package PackageList
                    RequestMode Service
                    ServiceCode
              );
use Type::Utils -all;
use Types::Standard -types;
use namespace::autoclean;

enum PickupType,
    [qw(
           DAILY_PICKUP
           DAILY
           CUSTOMER_COUNTER
           ONE_TIME_PICKUP
           ONE_TIME
           ON_CALL_AIR
           SUGGESTED_RETAIL
           SUGGESTED_RETAIL_RATES
           LETTER_CENTER
           AIR_SERVICE_CENTER
   )];

enum CustomerClassification,
    [qw(
           WHOLESALE
           OCCASIONAL
           RETAIL

   )];

enum RequestMode, # there are probably more
    [qw(
           rate
           shop
   )];

enum ServiceCode,
    [qw(
        NEXT_DAY_AIR
        2ND_DAY_AIR
        GROUND
        WORLDWIDE_EXPRESS
        WORLDWIDE_EXPEDITED
        STANDARD
        3_DAY_SELECT
        3DAY_SELECT
        NEXT_DAY_AIR_SAVER
        NEXT_DAY_AIR_EARLY_AM
        WORLDWIDE_EXPRESS_PLUS
        2ND_DAY_AIR_AM
   )];

class_type Address, { class => 'Net::UPS2::Address' };
coerce Address, from Str, via {
    require Net::UPS2::Address;
    Net::UPS2::Address->new({postal_code => $_});
};

class_type Package, { class => 'Net::UPS2::Package' };

declare PackageList, as ArrayRey[Package];
coerce PackageList, from Package, via { [ $_ ] };

class_type Service, { class => 'Net::UPS2::Service' };
coerce Service, from Str, via {
    require Net::UPS2::Service;
    Net::UPS2::Service->new_from_label($_);
};


duck_type Cache, [qw(get set)];

1;
