package Font::Bitmap::BDF::Glyph;
use warnings;
use strict;

use lib "../../..";
use Mooo;

sub new {
    my ($class, %args) = @_;
    my $self = bless({}, $class);
    $self->init(%args);
    my @args = %args;
    # print STDERR ("$self @args\n");
    return $self;
}

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

# if non-zero, either negative or positive, there are pixels
# to the left of zero.
has negativeLeftOffset => (is => 'rw', default => 0);

has font => (is => 'rw');

use Font::Bitmap::BDF::AdobeGlyphListForNewFonts qw(adobeGlyphName);
use Font::Bitmap::BDF::Constants qw(:all);

use POSIX qw(round);
use List::Util qw(max all min);
use Data::Dumper qw(Dumper);

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
    $self->finalizeWidth();
    $self->finalizeHeight();
    $self->finalizeEncoding();
}

sub trim {
    my ($self) = @_;
    $self->trimEmptyLinesFromBottom();
    $self->trimEmptyLinesFromTop();
    $self->trimEmptyColumns();
}

sub finalizeEncoding {
    my ($self) = @_;
    if ($self->name =~ m{^\s*(?:U\+|0x)(?<codepoint>[[:xdigit:]]+)}xi) {
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
        if ($data->{format} eq 'pixels') {
            my $pixels = $data->{pixels};
            my $hex  = $data->{hex};
            if (defined $pixels && !defined $hex) {
                $pixels =~ s{\S}{1}g;
                $pixels =~ s{\s}{0}g;
                if (length($pixels) % 4 != 0) {
                    $pixels .= '0' x (4 - length($pixels) % 4);
                }
                $hex = uc unpack('H*', pack('B*', $pixels));
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

    if (!defined $self->boundingBoxWidth && defined $self->font->boundingBoxWidth) {
        $self->boundingBoxWidth($self->font->boundingBoxWidth);
    }
    if (!defined $self->boundingBoxHeight && defined $self->font->boundingBoxHeight) {
        $self->boundingBoxHeight($self->font->boundingBoxHeight);
    }
    if (!defined $self->boundingBoxOffsetX && defined $self->font->boundingBoxOffsetX) {
        $self->boundingBoxOffsetX($self->font->boundingBoxOffsetX);
    }
    if (!defined $self->boundingBoxOffsetY && defined $self->font->boundingBoxOffsetY) {
        $self->boundingBoxOffsetY($self->font->boundingBoxOffsetY);
    }

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
        } else {
            $self->boundingBoxOffsetY(0);
        }
    }
    if (!defined $self->boundingBoxWidth) {
        my $width = 0;
        foreach my $data (@{$self->bitmapData}) {
            print STDERR Dumper($data) . "\n";
            if ($data->{format} eq 'pixels') {
                $width = max($width, length($data->{pixels}));
            } elsif ($data->{format} eq 'hex') {
                $width = max($width, 4 * length($data->{hex}));
            }
        }
        $self->boundingBoxWidth($width);
        printf STDERR ("finalizeBoundingBox: [1] set boundingBoxWidth to %s\n", $self->boundingBoxWidth);
    }
    if (!defined $self->boundingBoxOffsetX) {
        $self->boundingBoxOffsetX(-1 * abs($self->negativeLeftOffset));
    }
}

sub trimEmptyLinesFromBottom {
    my ($self) = @_;
    while (scalar @{$self->bitmapData} && $self->bitmapData->[-1]->{hex} =~ m{^0+$}) {
        pop(@{$self->bitmapData});
        $self->boundingBoxOffsetY($self->boundingBoxOffsetY + 1);
        $self->boundingBoxHeight($self->boundingBoxHeight - 1);
    }
}

sub trimEmptyLinesFromTop {
    my ($self) = @_;
    while (scalar @{$self->bitmapData} &&
           $self->bitmapData->[0]->{hex} =~ m{^0+$}) {
        shift(@{$self->bitmapData});
        $self->boundingBoxHeight($self->boundingBoxHeight - 1);
    }
}

sub trimEmptyColumns {
    my ($self) = @_;
    foreach my $data (@{$self->bitmapData}) {
        $data->{bin} = unpack('B*', pack('H*', $data->{hex}));
    }
    $self->trimEmptyColumnsFromLeft();
    $self->trimEmptyColumnsFromRight();
    foreach my $data (@{$self->bitmapData}) {
        $data->{hex} = unpack('H*', pack('B*', $data->{bin}));
    }
}

sub trimEmptyColumnsFromLeft {
    my ($self) = @_;
    my @shifts = map { $_->{bin} =~ m{^(0+)} ? length($1) : 0 } @{$self->bitmapData};
    my $shift = min(@shifts);
    if ($shift) {
        foreach my $data (@{$self->bitmapData}) {
            $data->{bin} = substr($data->{bin}, $shift);
        }
        $self->boundingBoxOffsetX($self->boundingBoxOffsetX + $shift);
        $self->boundingBoxWidth($self->boundingBoxWidth - $shift);
        printf STDERR ("finalizeBoundingBox: [2] set boundingBoxWidth to %s\n", $self->boundingBoxWidth);
    }
}

sub trimEmptyColumnsFromRight {
    my ($self) = @_;
    foreach my $data (@{$self->bitmapData}) {
        $data->{bin} =~ s{0+$}{};
    }
    my $length = max( map { length($_->{bin}) } @{$self->bitmapData});
    foreach my $data (@{$self->bitmapData}) {
        $data->{bin} .= '0' x ($length - length($data->{bin}));
    }
    $self->boundingBoxWidth($length);
    printf STDERR ("finalizeBoundingBox: [3] set boundingBoxWidth to %s\n", $self->boundingBoxWidth);
}

sub finalizeWidth {
    my ($self) = @_;
    if (defined $self->sWidthX && defined $self->dWidthX) {
        return;
    }
    my $pointSize = $self->font->pointSize // 0;
    my $xResolution = $self->font->xResolution // 0;
    if ($pointSize && $xResolution) {
        if (defined $self->sWidthX) {
            $self->dWidthX(round($self->sWidthX * $pointSize / 1000 * $xResolution / POINTS_PER_INCH));
            printf STDERR ("[DEBUG] finalizeWidth: [1] just computed dWidthX; setting to %s\n", $self->dWidthX);
        } elsif (defined $self->dWidthX) {
            $self->sWidthX(round($self->dWidthX * 1000 / $pointSize * POINTS_PER_INCH / $xResolution));
            printf STDERR ("[DEBUG] finalizeWidth: [2] just computed sWidthX; setting to %s\n", $self->sWidthX);
        } else {
            $self->dWidthX($self->boundingBoxWidth);
            $self->sWidthX(round($self->dWidthX * 1000 / $pointSize * POINTS_PER_INCH / $xResolution));
            printf STDERR ("[DEBUG] finalizeWidth: [3] just computed dWidthX; setting to %s\n", $self->dWidthX);
            printf STDERR ("[DEBUG] finalizeWidth: [3] just computed sWidthX; setting to %s\n", $self->sWidthX);
        }
    }
}

sub finalizeHeight {
    my ($self) = @_;
    if (defined $self->sWidthY && defined $self->dWidthY) {
        return;
    }
    if (defined $self->sWidthY) {
        $self->dWidthY(round($self->sWidthY * $self->font->pointSize / 1000 * $self->font->yResolution / POINTS_PER_INCH));
        printf STDERR ("[DEBUG] finalizeWidth: [4] just computed dWidthY = %s\n", $self->dWidthY);
    } elsif (defined $self->dWidthY) {
        $self->sWidthY(round($self->dWidthY * 1000 / $self->font->pointSize * POINTS_PER_INCH / $self->font->yResolution));
        printf STDERR ("[DEBUG] finalizeWidth: [5] just computed sWidthY = %s\n", $self->sWidthY);
    } else {
        $self->dWidthY(0);     # assuming horizontal writing mode
        $self->sWidthY(0);
        printf STDERR ("[DEBUG] finalizeWidth: [6] assuming horizontal writing mode; setting dWidthY and sWidthY to 0\n");
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

# DO NOT RUN AFTER MODIFYING BOUNDING BOX
sub guessSDWidths {
    my ($self) = @_;
    if (defined $self->boundingBoxWidth && defined $self->boundingBoxOffsetX) {
        if (!defined $self->dWidthX) {
            $self->dWidthX($self->boundingBoxWidth + $self->boundingBoxOffsetX);
            printf STDERR ("guessSDWidths: computed dWidthX; setting to %s\n", $self->dWidthX);
        }
        if (!defined $self->dWidthY) {
            $self->dWidthY(0);
            printf STDERR ("guessSDWidths: assuming horiz. writing mode; setting dWidthY to %s\n", $self->dWidthY);
        }
    }
}

sub matchSDWidths {
    my ($self) = @_;
    # printf STDERR ("%s font is %s\n", $self, $self->font // '(undef)');
    my $rx = $self->font->xResolution;
    my $ry = $self->font->yResolution;
    my $p = $self->font->pointSize;
    if (!defined $self->dWidthX && defined $self->sWidthX) {
        if (defined $rx && defined $p) {
            $self->dWidthX($self->sWidthX * $p / 1000 * $rx / POINTS_PER_INCH);
            printf STDERR ("matchSDWidths: computed dWidthX; setting to %s\n", $self->dWidthX);
        }
    }
    if (!defined $self->dWidthY && defined $self->sWidthY) {
        if (defined $ry && defined $p) {
            $self->dWidthY($self->sWidthY * $p / 1000 * $ry / POINTS_PER_INCH);
            printf STDERR ("matchSDWidths: computed dWidthY; setting to %s\n", $self->dWidthY);
        }
    }
    if (!defined $self->sWidthX && defined $self->dWidthX) {
        if (defined $rx && defined $p) {
            $self->sWidthX($self->dWidthX * 1000 / $p * POINTS_PER_INCH / $rx);
            printf STDERR ("matchSDWidths: computed sWidthX; setting to %s\n", $self->sWidthX);
        }
    }
    if (!defined $self->sWidthY && defined $self->dWidthY) {
        if (defined $rx && defined $p) {
            $self->sWidthY($self->dWidthY * 1000 / $p * POINTS_PER_INCH / $ry);
            printf STDERR ("matchSDWidths: computed sWidthY; setting to %s\n", $self->sWidthY);
        }
    }
}

sub fix {
    my ($self) = @_;
    # placeholder
}

1;
