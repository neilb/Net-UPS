#!perl
use strict;
use warnings;
use Test::Most;
use Net::UPS2::Package;

my @data = (
    { width => 10, length => 20, height => 30, weight => 40,
      measurement_system => 'english',
      oversized => 0, comment => 'ok' },

    { width => 10, length => 20, height => 30, weight => 180,
      measurement_system => 'english',
      fail => 1, comment => 'too heavy' },
    { width => 100, length => 20, height => 20, weight => 40,
      measurement_system => 'english',
      fail => 1, comment => 'excessive girth' },
    { width => 110, length => 10, height => 10, weight => 40,
      measurement_system => 'english',
      fail => 1, comment => 'excessive length' },

    { width => 20, length => 15, height => 20, weight => 20,
      measurement_system => 'english',
      oversized => 1, comment => 'OS1' },
    { width => 20, length => 25, height => 24, weight => 40,
      measurement_system => 'english',
      oversized => 2, comment => 'OS2' },
    { width => 30, length => 30, height => 25, weight => 40,
      measurement_system => 'english',
      oversized => 3, comment => 'OS3' },

    { width => 20, length => 15, height => 20, weight => 40,
      measurement_system => 'english',
      oversized => 0, comment => 'not OS1 due to weight' },
    { width => 20, length => 25, height => 24, weight => 80,
      measurement_system => 'english',
      oversized => 0, comment => 'not OS2 due to weight' },
    { width => 30, length => 30, height => 25, weight => 100,
      measurement_system => 'english',
      oversized => 0, comment => 'not OS3 due to weight' },

    { width => 1, length => 2, height => 100, weight => 20,
      measurement_system => 'english',
      oversized => 1, comment => 'check for size sorting' },
);

for my $d (@data) {
    my ($oversized,$fail,$comment) =
        (delete @$d{qw(oversized fail comment)});

    my $p = Net::UPS2::Package->new($d);

    if ($fail) {
        throws_ok {
            $p->is_oversized;
        } 'Net::UPS2::Exception::BadPackage',
            "$comment - expected failure";
    }
    else {
        is($p->is_oversized,$oversized,
           "$comment - expected oversized class");
    }
}

done_testing();
