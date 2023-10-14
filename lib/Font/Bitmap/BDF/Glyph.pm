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
    # printf STDERR ("[DEBUG] %s: new glyph %s\n", ref $self, $self->{name});
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
    # $self->finalizeWidth();
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
    if ($self->name =~ m{^\s*(?<name>(?:U\+|0x)(?<codepoint>[[:xdigit:]]+))}xi) {
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
            my $hex = $data->{hex};
            if (defined $pixels && !defined $hex) {
                if ($pixels eq '') {
                    $pixels = ' '; # best effort
                }
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

    if (!defined $self->boundingBoxHeight) {
        $self->boundingBoxHeight(scalar @{$self->bitmapData});
    }
    if (!defined $self->boundingBoxOffsetY) {
        my $baselineIndex;
        foreach my $data (@{$self->bitmapData}) {
            my $sm = $data->{startMarker} // '';
            my $em = $data->{endMarker} // '';
            if ($sm eq '_' || $sm eq '+' || $em eq '_' || $em eq '+') { # BASELINE INDICATOR
                $baselineIndex = $data->{index};
                last;
            }
        }
        if (defined $baselineIndex) {
            $self->boundingBoxOffsetY($baselineIndex - scalar(@{$self->bitmapData}) + 1);
        } else {
            $self->boundingBoxOffsetY(0);
        }
    }
    if (!defined $self->boundingBoxWidth) {
        my $spacing = lc($self->font->properties->get('SPACING') // 'm');
        $spacing =~ s{^"}{};
        $spacing =~ s{"$}{};
        if (defined $spacing && ($spacing eq 'm' || $spacing eq 'c')) {
            my $bbw = $self->font->boundingBoxWidth;
            if (defined $bbw) {
                $self->boundingBoxWidth($bbw);
            } else {
                die(sprintf("%s: font has no bounding box width and spacing %s is monospace\n", $self->font->filename, $self->name));
            }
        } else {
            die(sprintf("%s: char %s has no bounding box width and spacing %s is not monospace\n", $self->font->filename, $self->name, $spacing // '(undef)'));
        }
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
}

sub finalizeWidth {
    my ($self) = @_;
    if (defined $self->sWidthX && defined $self->dWidthX) {
        return;
    }
    my $pointSize = $self->font->pointSize // 0;
    my $xResolution = $self->font->xResolution // 0;
    if (defined $self->sWidthX) {
        my $dWidthX = round($self->sWidthX * $pointSize / 1000 * $xResolution / POINTS_PER_INCH);
        $self->dWidthX($dWidthX);
    } elsif (defined $self->dWidthX) {
        my $sWidthX = round($self->dWidthX * 1000 / $pointSize * POINTS_PER_INCH / $xResolution);
        $self->sWidthX($sWidthX);
    } else {
        my $dWidthX = $self->boundingBoxWidth + $self->boundingBoxOffsetX;
        my $sWidthX = round($dWidthX * 1000 / $pointSize * POINTS_PER_INCH / $xResolution);
        if (!defined $self->font->dWidthX) {
            $self->dWidthX($dWidthX);
        }
        if (!defined $self->font->sWidthX) {
            $self->sWidthX($sWidthX);
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
    } elsif (defined $self->dWidthY) {
        $self->sWidthY(round($self->dWidthY * 1000 / $self->font->pointSize * POINTS_PER_INCH / $self->font->yResolution));
    } else {
        # assuming horizontal writing mode
        $self->dWidthY(0);
        $self->sWidthY(0);
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
    my $swx = $self->computeSWidthX();
    my $dwx = $self->computeDWidthX();
    if (defined $swx && defined $self->sWidthY) {
        $result .= sprintf("SWIDTH %d %d\n", round($swx), round($self->sWidthY));
    }
    if (defined $dwx && defined $self->dWidthY) {
        $result .= sprintf("DWIDTH %d %d\n", round($dwx), round($self->dWidthY));
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

sub computeSWidthX {
    my ($self) = @_;
    my $sw = $self->sWidthX;
    my $dw = $self->dWidthX;                      # 7
    my $pt = $self->font->computePointSize();     # 12
    my $xres = $self->font->computeXResolution(); # 210
    my $yres = $self->font->computeYResolution(); # 96
    my $bbw = $self->boundingBoxWidth;            # 7
    my $bbx = $self->boundingBoxOffsetX;          # 0
    if (defined $sw) {
        printf STDERR ("[DEBUG] swidth is defined as $sw\n");
        return $sw;
    }
    if (defined $dw) {
        my $sw = round($dw / $xres * POINTS_PER_INCH / ($pt/10) * 1000) if defined $dw;
        printf STDERR ("[DEBUG] dw = %s; xres = %s; 72 ppi; fontsize = %s => swidth = %s\n", $dw, $xres, $pt, $sw);
        return $sw;
    }
    if (defined $bbw && defined $bbx) {
        my $dw = $bbw + $bbx;
        if (defined $dw) {
            my $sw = round($dw / $xres * POINTS_PER_INCH / ($pt/10) * 1000);
            printf STDERR ("[DEBUG] dw = %s; xres = %s; 72 ppi; fontsize = %s => swidth = %s\n", $dw, $xres, $pt, $sw);
            return $sw;
        }
    }
    return;
}

# if dwidth = 7 pixels
# we need to compute the swidth - in terms of thousandths of the vertical font size or units of 12/1000 pt
#    width of each character = 7 / 105 = 1/15 inch
#    or 72/15 points = 4.8 points
#    4.8pt / 12pt = 0.4em
#    * .4em * 1000/em = 400

sub computeDWidthX {
    my ($self) = @_;
    my $sw = $self->sWidthX;
    my $dw = $self->dWidthX;
    my $pt = $self->font->computePointSize();
    my $xres = $self->font->computeXResolution();
    my $bbw = $self->boundingBoxWidth;
    my $bbx = $self->boundingBoxOffsetX;
    return $dw if defined $dw;
    return round($sw * $pt / 1000 * $xres / POINTS_PER_INCH) if defined $sw;
    return $bbw + $bbx if (defined $bbw && defined $bbx);
    return;
}

sub fix {
    my ($self) = @_;
    # placeholder
}

sub doubleStrike {
    my ($self) = @_;
    foreach my $data (@{$self->bitmapData}) {
        my $hex = $data->{hex};
        my $pixels = $data->{pixels};
        if (defined $hex) {     # [0-9A-Fa-f]...
            my @hex = map { hex($_) } split('', $hex);
            my @newHex = @hex;
            for (my $i = 0; $i < scalar @hex; $i += 1) {
                $newHex[$i] |= ($hex[$i] >> 1);
                if ($i) {
                    $newHex[$i] |= (($hex[$i - 1] & 1) << 3);
                }
            }
            $data->{hex} = join('', map { sprintf('%01X', $_) } @newHex);
        }
        if (defined $pixels) {
            my @pixels = split('', $pixels);
            my @newPixels = @pixels;
            for (my $i = 0; $i < scalar @pixels; $i += 1) {
                if ($i) {
                    $newPixels[$i] |= $pixels[$i - 1];
                }
            }
            $data->{pixels} = join('', map { $_ ? '1' : '0' } @newPixels);
        }
    }
}

1;
