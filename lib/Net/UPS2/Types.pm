package Net::UPS2::Types;
use strict;
use warnings;
use Type::Library
    -base,
    -declare => qw( PickupType CustomerClassification
                    Cache UserAgent
                    Address Package PackageList
                    RequestMode Service
                    ServiceCode ServiceLabel
                    PackagingType MeasurementSystem
                    Measure MeasurementUnit Currency
                    Tolerance
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
           01
           02
           03
           07
           08
           11
           12
           12
           13
           14
           54
           59
           65
           86
           85
           83
           82
   )];

enum ServiceLabel,
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
        SAVER
        TODAY_EXPRESS_SAVER
        TODAY_EXPRESS
        TODAY_DEDICATED_COURIER
        TODAY_STANDARD
   )];

enum PackagingType,
    [qw(
        LETTER
        PACKAGE
        TUBE
        UPS_PAK
        UPS_EXPRESS_BOX
        UPS_25KG_BOX
        UPS_10KG_BOX
   )];

enum MeasurementSystem,
    [qw(
           metric
           english
   )];

enum MeasurementUnit,
    [qw(
           LBS
           KGS
           IN
           CM
   )];

declare Currency,
    as Str;

declare Measure,
    as StrictNum,
    where { $_ >= 0 },
    inline_as {
        my ($constraint, $varname) = @_;
        my $perlcode =
            $constraint->parent->inline_check($varname)
                . "&& ($varname >= 0)";
        return $perlcode;
    },
    message { ($_//'<undef>').' is not a valid measure, it must be a non-negative number' };

declare Tolerance,
    as StrictNum,
    where { $_ >= 0 && $_ <= 1 },
    inline_as {
        my ($constraint, $varname) = @_;
        my $perlcode =
            $constraint->parent->inline_check($varname)
                . "&& ($varname >= 0 && $varname <= 1)";
        return $perlcode;
    },
    message { ($_//'<undef>').' is not a valid tolerance, it must be a number between 0 and 1' };

class_type Address, { class => 'Net::UPS2::Address' };
coerce Address, from Str, via {
    require Net::UPS2::Address;
    Net::UPS2::Address->new({postal_code => $_});
};

class_type Package, { class => 'Net::UPS2::Package' };

declare PackageList, as ArrayRef[Package];
coerce PackageList, from Package, via { [ $_ ] };

class_type Service, { class => 'Net::UPS2::Service' };
coerce Service, from Str, via {
    require Net::UPS2::Service;
    Net::UPS2::Service->new({label=>$_});
};


duck_type Cache, [qw(get set)];
duck_type UserAgent, [qw(request)];

1;
