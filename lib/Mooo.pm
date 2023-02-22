package Mooo;
use warnings;
use strict;

use base 'Exporter';
our @EXPORT = qw(has init);
our @EXPORT_OK = qw(has init);

sub has(*;@) {
    no strict 'refs';
    my ($name, %args) = @_;
    my $class = caller;
    my $defaultshash = \%{"${class}::DEFAULTS"};
    if (exists $args{default}) {
        $defaultshash->{$name} = $args{default};
    }
    my $sub = sub {
        my $self = shift;
        return $self->{$name} = shift if scalar @_;
        return $self->{$name};
    };
    *{"${class}::${name}"} = $sub;
}

sub init {
    my $self = shift;
    my $class = ref $self;
    no strict 'refs';
    my $defaultshash = \%{"${class}::DEFAULTS"};
    foreach my $key (keys %$defaultshash) {
        my $default = $defaultshash->{$key};
        if (ref $default eq 'CODE') {
            $self->{$key} = &$default($self);
        } else {
            $self->{$key} = $default;
        }
    }
}

1;
