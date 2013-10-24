package Net::UPS2::Exception;
use strict;
use warnings;
use Moo;
with 'Throwable','StackTrace::Auto';
use overload
  q{""}    => 'as_string',
  fallback => 1;

around _build_stack_trace_args => sub {
    my ($orig,$self) = @_;

    my $ret = $self->$orig();
    push @$ret, (
        no_refs => 1,
        respect_overload => 1,
        message => '',
        indent => 1,
    );

    return $ret;
};

sub as_string { "something bad happened at ". $_[0]->stack_trace }

{package Net::UPS2::Exception::HTTPError;
 use strict;
 use warnings;
 use Moo;
 extends 'Net::UPS2::Exception';

 has request => ( is => 'ro', required => 1 );
 has response => ( is => 'ro', required => 1 );

 sub as_string {
     my ($self) = @_;

     return sprintf 'Error %sin %s: %s, at %s',
         $self->request->method,$self->request->uri,
         $self->response->status_line,
         $self->stack_trace;
 }
}

{package Net::UPS2::Exception::UPSError;
 use strict;
 use warnings;
 use Moo;
 extends 'Net::UPS2::Exception';

 has error => ( is => 'ro', required => 1 );

 sub as_string {
     my ($self) = @_;

     return sprintf 'UPS returned an error: %s, severity %s, code %d, at %s',
         $self->error->{ErrorDescription},
         $self->error->{ErrorSeverity},
         $self->error->{ErrorCode},
         $self->stack_trace;
 }
}

1;
