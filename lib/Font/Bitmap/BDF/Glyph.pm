package Font::Bitmap::BDF::Glyph;
use warnings;
use strict;

use Moo;

has name                => (is => 'rw'); # should be adobe glyph name
has encoding            => (is => 'rw'); # integer
has nonStandardEncoding => (is => 'rw'); # integer

has sWidthX  => (is => 'rw');
has sWidthY  => (is => 'rw');
has sWidth1X => (is => 'rw');
has sWidth1Y => (is => 'rw');

has dWidthX  => (is => 'rw');
has dWidthY  => (is => 'rw');
has dWidth1X => (is => 'rw');
has dWidth1Y => (is => 'rw');

has vVectorX => (is => 'rw');
has vVectorY => (is => 'rw');

has boundingBoxWidth   => (is => 'rw'); # integer pixels
has boundingBoxHeight  => (is => 'rw'); # integer pixels
has boundingBoxOffsetX => (is => 'rw'); # integer pixels
has boundingBoxOffsetY => (is => 'rw'); # integer pixels

has bitmapData => (is => 'rw', default => sub { return []; });

has font => (is => 'rw');

use Font::Bitmap::BDF::AdobeGlyphListForNewFonts qw(adobeGlyphName);

use POSIX qw(round);
use List::Util qw(max);

sub appendBitmapData {
    my ($self, $data) = @_;
    if (ref $data eq 'HASH') {
        $data->{hex} = uc $data->{hex} if defined $data->{hex};
    } elsif (ref $data eq '') {
        $data = uc $data;
    }
    push(@{$self->bitmapData}, $data);
}

sub finalize {
    my ($self) = @_;
    $self->finalizeHex();
    $self->finalizeIndexes();
    $self->finalizeBoundingBox();
    if ($self->name =~ m{^\s*U\+(?<codepoint>[[:xdigit:]]+)}xi) {
        if (!defined $self->encoding) {
            $self->encoding(hex($+{codepoint}));
        }
        if ($self->encoding != -1) {
            $self->name(adobeGlyphName($self->encoding));
        }
    }
}

sub finalizeHex {
    my ($self) = @_;
    foreach my $data (@{$self->bitmapData}) {
        if ($data->{format} eq 'dots') {
            my $dots = $data->{dots};
            my $hex  = $data->{hex};
            if (defined $dots && !defined $hex) {
                $dots =~ s{\S}{1}g;
                $dots =~ s{\s}{0}g;
                if (length($dots) % 4 != 0) {
                    $dots .= '0' x (4 - length($dots) % 4);
                }
                $hex = uc unpack('H*', pack('B*', $dots));
                $data->{hex} = $hex;
            }
        } elsif ($data->{format} eq 'hex') {
            if (defined $data->{hex}) {
                if (length($data->{hex}) % 2 != 0) {
                    $data->{hex} .= '0';
                }
            }
        }
    }
}

sub finalizeIndexes {
    my ($self) = @_;
    my $index = 0;
    foreach my $data (@{$self->bitmapData}) {
        $data->{index} = $index;
        $index += 1;
    }
}

sub finalizeBoundingBox {
    my ($self) = @_;
    if (!defined $self->boundingBoxHeight) {
        $self->boundingBoxHeight(scalar @{$self->bitmapData});
    }
    if (!defined $self->boundingBoxOffsetY) {
        my $baselineIndex;
        foreach my $data (@{$self->bitmapData}) {
            my $sm = $data->{startMarker} // '';
            my $em = $data->{endMarker} // '';
            if ($sm eq '_' || $sm eq '+' || $em eq '_' || $em eq '+') {
                $baselineIndex = $data->{index};
                last;
            }
        }
        if (defined $baselineIndex) {
            $self->boundingBoxOffsetY((scalar(@{$self->bitmapData}) - $baselineIndex - 1) * -1);
        }
    }
    if (!defined $self->boundingBoxWidth) {
        my $width = 0;
        foreach my $data (@{$self->bitmapData}) {
            if ($data->{format} eq 'dots') {
                $width = max($width, length($data->{dots}));
            } elsif ($data->{format} eq 'hex') {
                $width = max($width, 4 * length($data->{hex}));
            }
        }
        $self->boundingBoxWidth($width);
    }
    if (!defined $self->boundingBoxOffsetX) {
        $self->boundingBoxOffsetX(0);
    }
}

sub toString {
    my ($self, @args) = @_;
    my $result = '';
    $result .= sprintf("STARTCHAR %s\n", $self->name);
    if (defined $self->nonStandardEncoding) {
        $result .= sprintf("ENCODING %d %d\n", round($self->encoding), round($self->nonStandardEncoding));
    } else {
        $result .= sprintf("ENCODING %d\n", round($self->encoding));
    }
    if (defined $self->boundingBoxWidth ||
        defined $self->boundingBoxHeight ||
        defined $self->boundingBoxOffsetX ||
        defined $self->boundingBoxOffsetY) {
        $result .= sprintf("BBX %d %d %d %d\n",
                           round($self->boundingBoxWidth // 0),
                           round($self->boundingBoxHeight // 0),
                           round($self->boundingBoxOffsetX // 0),
                           round($self->boundingBoxOffsetY // 0));
    }
    if (defined $self->sWidthX && defined $self->sWidthY) {
        $result .= sprintf("SWIDTH %d %d\n", round($self->sWidthX), round($self->sWidthY));
    }
    if (defined $self->dWidthX && defined $self->dWidthY) {
        $result .= sprintf("DWIDTH %d %d\n", round($self->dWidthX), round($self->dWidthY));
    }
    if (defined $self->sWidth1X && defined $self->sWidth1Y) {
        $result .= sprintf("SWIDTH1 %d %d\n", round($self->sWidth1X), round($self->sWidth1Y));
    }
    if (defined $self->dWidth1X && defined $self->dWidth1Y) {
        $result .= sprintf("DWIDTH1 %d %d\n", round($self->dWidth1X), round($self->dWidth1Y));
    }
    if (defined $self->vVectorX && defined $self->vVectorY) {
        $result .= sprintf("VVECTOR %d %d\n", round($self->vVectorX), round($self->vVectorY));
    }
    $result .= "BITMAP\n";
    foreach my $data (@{$self->bitmapData}) {
        if (defined $data->{hex}) {
            $result .= sprintf("%s\n", uc $data->{hex});
        }
    }
    $result .= "ENDCHAR\n";
    return $result;
}

sub assumeSDWidths {
    my ($self) = @_;
    if (defined $self->boundingBoxWidth && defined $self->boundingBoxOffsetX) {
        if (!defined $self->dWidthX) {
            $self->dWidthX($self->boundingBoxWidth + $self->boundingBoxOffsetX);
            $self->dWidthY(0) if !defined $self->dWidthY;
        }
    }
}

sub fix {
    my ($self) = @_;
    # placeholder
}

sub fixSDWidths {
    my ($self) = @_;
    my $rx = $self->font->xResolution;
    my $ry = $self->font->yResolution;
    my $p = $self->font->pointSize;
    if (!defined $self->dWidthX && defined $self->sWidthX) {
        if (defined $rx && defined $p) {
            $self->dWidthX($self->sWidthX * $p / 1000 * $rx / 72);
        }
    }
    if (!defined $self->dWidthY && defined $self->sWidthY) {
        if (defined $ry && defined $p) {
            $self->dWidthY($self->sWidthY * $p / 1000 * $ry / 72);
        }
    }
    if (!defined $self->sWidthX && defined $self->dWidthX) {
        if (defined $rx && defined $p) {
            $self->sWidthX($self->dWidthX * 1000 / $p * 72 / $rx);
        }
    }
    if (!defined $self->sWidthY && defined $self->dWidthY) {
        if (defined $rx && defined $p) {
            $self->sWidthY($self->dWidthY * 1000 / $p * 72 / $ry);
        }
    }
}

1;
