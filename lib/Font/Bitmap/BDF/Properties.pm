package Font::Bitmap::BDF::Properties;
use warnings;
use strict;

use Moo;

has propertyList => (is => 'rw', default => sub { return []; });
has propertyHash => (is => 'rw', default => sub { return {}; });
has propertyArrays => (is => 'rw', default => sub { return {}; });

has font => (is => 'rw');

use Scalar::Util qw(looks_like_number);

# $props->append($name, $value);
sub append {
    my ($self, $name, $value) = @_;
    $name = uc $name;

    my $prop = { name => $name, value => $value };
    push(@{$self->propertyList}, $prop);

    $self->propertyHash->{$name} = $value;
    push(@{$self->propertyArrays->{$name}}, $value);
}

# $value = $props->get($name);
sub get {
    my ($self, $name) = @_;
    $name = uc $name;

    return $self->propertyHash->{$name};
}

# @values = $props->getAll($name);
sub getAll {
    my ($self, $name) = @_;
    $name = uc $name;

    my $array = $self->propertyArrays->{$name};
    return @$array if $array;
    return;
}

# $props->remove($name);
sub remove {
    my ($self, $name) = @_;
    $name = uc $name;

    @{$self->propertyList} = grep { $_->{name} ne $name } @{$self->propertyList};
    delete $self->propertyHash->{$name};
    delete $self->propertyArrays->{$name};
}

# $props->set($name, $value);
# $props->set($name, @values);
sub set {
    my ($self, $name, @values) = @_;
    $name = uc $name;

    $self->remove($name);

    foreach my $value (@values) {
        $self->append($name, $value);
    }

    return @values if wantarray;
    return $values[-1] if scalar @values;
    return;
}

sub setByDefault {
    my ($self, $name, @values) = @_;
    if (defined $self->get($name)) {
        return;
    }
    $self->set($name, @values);
}

# $numeric = $props->getNumeric($name);
sub getNumeric {
    my ($self, $name) = @_;
    my $value = $self->get($name);
    if (defined $value && looks_like_number($value)) {
        return $value;
    }
    return;
}

sub setNumeric {
    my ($self, $name, $value) = @_;
    if (looks_like_number($value)) {
        $self->set($name, $value);
    }
}

# $string = $props->toString();
sub toString {
    my ($self, @args) = @_;
    my $count = scalar @{$self->propertyList};
    if (!$count) {
        return '';
    }
    my $result = '';
    $result .= sprintf("STARTPROPERTIES %d\n", $count);
    foreach my $prop (@{$self->propertyList}) {
        $result .= sprintf("%s %s\n", uc $prop->{name}, $prop->{value});
    }
    $result .= "ENDPROPERTIES\n";
    return $result;
}

1;
