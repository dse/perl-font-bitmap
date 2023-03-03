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
    # printf STDERR ("[%s] has %s\n", $class, $name);
    if (exists $args{default}) {
        $defaultshash->{$name} = $args{default};
        # printf STDERR ("    with a default value\n");
    }
    my $sub = sub {
        my $self = shift;
        return $self->{$name} = shift if scalar @_;
        return $self->{$name};
    };
    *{"${class}::${name}"} = $sub;
}

sub init {
    my ($self, %args) = @_;
    my $class = ref $self;
    no strict 'refs';
    my $defaultshash = \%{"${class}::DEFAULTS"};
    my @keys = keys %$defaultshash;

    foreach my $key (keys %$defaultshash) {
        # printf STDERR ("%s [%s] setting %s\n", $class, $self, $key);
        my $default = $defaultshash->{$key};
        if (ref $default eq 'CODE') {
            $self->{$key} = $args{$key} // &$default($self);
        } else {
            $self->{$key} = $args{$key} // $default;
        }
    }
    foreach my $key (keys %args) {
        if (!exists $defaultshash->{$key}) {
            $self->{$key} = $args{$key};
        }
    }
}

1;
