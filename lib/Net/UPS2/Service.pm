package Net::UPS2::Service;
use strict;
use warnings;
use Moo;
use 5.10.0;
use Types::Standard qw(Str ArrayRef);
use Net::UPS2::Types ':types';

has code => (
    is => 'ro',
    isa => ServiceCode,
);

has label => (
    is => 'ro',
    isa => ServiceLabel,
);

has total_charges => (
    is => 'ro',
    isa => Measure,
    required => 0,
);
has rates => (
    is => 'ro',
    isa => ArrayRef, # TODO of what?
    required => 0,
);
has rated_packages => (
    is => 'ro',
    isa => ArrayRef, # TODO of what?
    required => 0,
);
has guaranteed_days => (
    is => 'ro',
    isa => Str,
    required => 0,
);

my %code_for_label = (
    NEXT_DAY_AIR            => '01',
    '2ND_DAY_AIR'           => '02',
    GROUND                  => '03',
    WORLDWIDE_EXPRESS       => '07',
    WORLDWIDE_EXPEDITED     => '08',
    STANDARD                => '11',
    '3_DAY_SELECT'          => '12',
    '3DAY_SELECT'           => '12',
    NEXT_DAY_AIR_SAVER      => '13',
    NEXT_DAY_AIR_EARLY_AM   => '14',
    WORLDWIDE_EXPRESS_PLUS  => '54',
    '2ND_DAY_AIR_AM'        => '59',
    SAVER                   => '65',
    TODAY_EXPRESS_SAVER     => '86',
    TODAY_EXPRESS           => '85',
    TODAY_DEDICATED_COURIER => '83',
    TODAY_STANDARD          => '82',
);
my %label_for_code = reverse %code_for_label;

sub label_for_code {
    my ($code) = @_;
    return $label_for_code{$code};
}

around BUILDARGS => sub {
    my ($orig,$class,@etc) = @_;
    my $args = $class->$orig(@etc);
    if ($args->{code} and not $args->{label}) {
        $args->{label} = $label_for_code{$args->{code}};
    }
    elsif ($args->{label} and not $args->{code}) {
        $args->{code} = $code_for_label{$args->{label}};
    }
    return $args;
};

sub name {
    my $self = shift;

    my $name = $self->label();
    $name =~ s/_/ /g;
    return $name;
}

sub cache_id { return $_[0]->code }

1;
