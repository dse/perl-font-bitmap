package Font::Bitmap::BDF;
use warnings;
use strict;

use Moo;

has formatVersion  => (is => 'rw'); # STARTFONT <number>
has comments       => (is => 'rw', default => sub { return []; });
has contentVersion => (is => 'rw');
has name           => (is => 'rw');       # FONT <string>

has pointSize   => (is => 'rw'); # in units of 1/72 inch
has xResolution => (is => 'rw'); # in dots per inch
has yResolution => (is => 'rw'); # in dots per inch

has boundingBoxWidth   => (is => 'rw'); # integer pixels
has boundingBoxHeight  => (is => 'rw'); # integer pixels
has boundingBoxOffsetX => (is => 'rw'); # integer pixels
has boundingBoxOffsetY => (is => 'rw'); # integer pixels

has metricsSet => (is => 'rw');         # integer

# in scalable units, or units of 1/1000th of the point size of the
# glyph
has sWidthX  => (is => 'rw');
has sWidthY  => (is => 'rw');
has sWidth1X => (is => 'rw');
has sWidth1Y => (is => 'rw');

# in device pixels
has dWidthX  => (is => 'rw');
has dWidthY  => (is => 'rw');
has dWidth1X => (is => 'rw');
has dWidth1Y => (is => 'rw');

# in device pixels
has vVectorX => (is => 'rw');
has vVectorY => (is => 'rw');

# to convert scalable units to device pixels,
#     multiply by <p> / 1000 then multiply by <r> / 72.
#                          ^
#                          |
#     this gets printers points

# to convert device pixels to scalable units,
#     multiply by 72 / <r> then multiply by 1000 / <p>.
#                        ^
#                        |
#     this gets printers points

has glyphs => (is => 'rw', default => sub { return []; });

has parser => (is => 'rw');

has properties => (
    is => 'rw', default => sub {
        my ($self) = @_;
        return Font::Bitmap::BDF::Properties->new(font => $self);
    }
);

has xlfdProperties => (
    is => 'rw', default => sub {
        my ($self) = @_;
        return Font::Bitmap::BDF::Properties->new(font => $self);
    }
);

use Font::Bitmap::BDF::Properties;
use Font::Bitmap::BDF::Glyph;
use Font::Bitmap::BDF::Constants qw(:all);

use POSIX qw(round);
use Scalar::Util qw(looks_like_number);

sub appendComment {
    my ($self, $comment) = @_;
    push(@{$self->comments}, $comment);
}

sub appendGlyph {
    my ($self, $glyph) = @_;
    push(@{$self->glyphs}, $glyph);
}

sub finalize {
    my ($self) = @_;
}

sub fix {
    my ($self) = @_;
    $self->fixResolution();
    $self->fixPixelAndPointSizes();
    $self->fixAscentDescent();
    $self->fixFromXLFDName();
    foreach my $glyph (@{$self->glyphs}) {
        $glyph->fix();
    }
}

sub assumePixelSize {
    my ($self) = @_;
    return unless defined $self->ascent;
    return unless defined $self->descent;
    if (!defined $self->pixelSize) {
        $self->pixelSize($self->ascent + $self->descent);
    }
}

sub assumeSDWidths {
    my ($self) = @_;
    foreach my $glyph (@{$self->glyphs}) {
        $glyph->assumeSDWidths();
    }
}

sub fixSDWidths {
    my ($self) = @_;
    foreach my $glyph (@{$self->glyphs}) {
        $glyph->fixSDWidths();
    }
}

# this is complicated.
#
# because while BDF *properties* have FONT_ASCENT and FONT_DESCENT,
# BDF *info* don't.  BDF info *does* have bounding box but it's not
# exactly the same.
sub fixAscentDescent {
    my ($self) = @_;
    if (defined $self->ascent && defined $self->descent) {
        my $height = $self->ascent + $self->descent;
        if (!defined $self->pixelSize2) {
            $self->pixelSize2($height);
        }
        if ($height == $self->pixelSize2) {
            if (!defined $self->ascent2) {
                $self->ascent2($self->ascent);
            }
            if (!defined $self->descent2) {
                $self->descent2($self->descent);
            }
        }
    }
}

sub fixResolution {
    my ($self) = @_;
    if (!defined $self->xResolution && defined $self->xResolution2) {
        $self->xResolution($self->xResolution2)
    }
    if (!defined $self->xResolution2 && defined $self->xResolution) {
        $self->xResolution2($self->xResolution)
    }
    if (!defined $self->yResolution && defined $self->yResolution2) {
        $self->yResolution($self->yResolution2)
    }
    if (!defined $self->yResolution2 && defined $self->yResolution) {
        $self->yResolution2($self->yResolution)
    }
}

sub fixPixelAndPointSizes {
    my ($self) = @_;
    if (!defined $self->pointSize && defined $self->pointSize2) {
        $self->pointSize($self->pointSize2);
    }
    if (!defined $self->pointSize2 && defined $self->pointSize) {
        $self->pointSize2($self->pointSize);
    }
    if (!defined $self->pixelSize && defined $self->pixelSize2) {
        $self->pixelSize($self->pixelSize2);
    }
    if (!defined $self->pixelSize2 && defined $self->pixelSize) {
        $self->pixelSize2($self->pixelSize);
    }
}

sub fixFromXLFDName {
    my ($self) = @_;
    my $name = $self->name;
    if (!defined $name) {
        return;
    }
    if ($name =~ m{^
                   -(?<foundry>[^-]+)?
                   -(?<familyName>[^-]+)?
                   -(?<weightName>[^-]+)?
                   -(?<slant>[^-]+)?
                   -(?<setwidthName>[^-]+)?
                   -(?<addStyleName>[^-]+)?
                   -(?<pixelSize>[^-]+)?
                   -(?<pointSize>[^-]+)?
                   -(?<resolutionX>[^-]+)?
                   -(?<resolutionY>[^-]+)?
                   -(?<spacing>[^-]+)?
                   -(?<averageWidth>[^-]+)?
                   -(?<charsetRegistry>[^-]+)?
                   -(?<charsetEncoding>[^-]+)?
                   $}xi) {
        my $foundry         = $+{foundry};
        my $familyName      = $+{familyName};
        my $weightName      = $+{weightName};
        my $slant           = $+{slant};
        my $setwidthName    = $+{setwidthName};
        my $addStyleName    = $+{addStyleName};
        my $pixelSize       = $+{pixelSize};
        my $pointSize       = $+{pointSize};
        my $resolutionX     = $+{resolutionX};
        my $resolutionY     = $+{resolutionY};
        my $spacing         = $+{spacing};
        my $averageWidth    = $+{averageWidth};
        my $charsetRegistry = $+{charsetRegistry};
        my $charsetEncoding = $+{charsetEncoding};
        $self->fixXLFDProperty('FOUNDRY', $foundry);
        $self->fixXLFDProperty('FAMILY_NAME', $familyName);
        $self->fixXLFDProperty('WEIGHT_NAME', $weightName);
        $self->fixXLFDProperty('SLANT', $slant);
        $self->fixXLFDProperty('SETWIDTH_NAME', $setwidthName);
        $self->fixXLFDProperty('ADD_STYLE_NAME', $addStyleName);
        $self->fixXLFDProperty('PIXEL_SIZE', $pixelSize);
        $self->fixXLFDProperty('POINT_SIZE', $pointSize);
        $self->fixXLFDProperty('RESOLUTION_X', $resolutionX);
        $self->fixXLFDProperty('RESOLUTION_Y', $resolutionY);
        $self->fixXLFDProperty('SPACING', $spacing);
        $self->fixXLFDProperty('AVERAGE_WIDTH', $averageWidth);
        $self->fixXLFDProperty('CHARSET_REGISTRY', $charsetRegistry);
        $self->fixXLFDProperty('CHARSET_ENCODING', $charsetEncoding);
    }
}

sub fixXLFDName {
    my ($self) = @_;
    my $foundry         = $self->properties->get('FOUNDRY');
    my $familyName      = $self->properties->get('FAMILY_NAME');
    my $weightName      = $self->properties->get('WEIGHT_NAME');
    my $slant           = $self->properties->get('SLANT');
    my $setwidthName    = $self->properties->get('SETWIDTH_NAME');
    my $addStyleName    = $self->properties->get('ADD_STYLE_NAME');
    my $pixelSize       = $self->properties->get('PIXEL_SIZE');
    my $pointSize       = $self->properties->get('POINT_SIZE');
    my $resolutionX     = $self->properties->get('RESOLUTION_X');
    my $resolutionY     = $self->properties->get('RESOLUTION_Y');
    my $spacing         = $self->properties->get('SPACING');
    my $averageWidth    = $self->properties->get('AVERAGE_WIDTH');
    my $charsetRegistry = $self->properties->get('CHARSET_REGISTRY');
    my $charsetEncoding = $self->properties->get('CHARSET_ENCODING');

    # all fourteen properties must be set and have a value that doesn't
    # contain: - ? * , "
    my $xlfdValid = 1;
    foreach ($foundry,
             $familyName,
             $weightName,
             $slant,
             $setwidthName,
             $addStyleName,
             $pixelSize,
             $pointSize,
             $resolutionX,
             $resolutionY,
             $spacing,
             $averageWidth,
             $charsetRegistry,
             $charsetEncoding) {
        if (!defined $_ || $_ =~ m{[\-\?\*\,\"]}) {
            $xlfdValid = 0;
            last;
        }
    }

    if ($xlfdValid) {
        my $xlfd = join("", map { "-$_" } ($foundry,
                                           $familyName,
                                           $weightName,
                                           $slant,
                                           $setwidthName,
                                           $addStyleName,
                                           $pixelSize,
                                           $pointSize,
                                           $resolutionX,
                                           $resolutionY,
                                           $spacing,
                                           $averageWidth,
                                           $charsetRegistry,
                                           $charsetEncoding));
        $self->name($xlfd);
    }
}

sub fixXLFDProperty {
    my ($self, $propName, $value) = @_;

    if (defined $value) {
        $self->xlfdProperties->setByDefault($propName, $value);
        $self->properties->setByDefault($propName, $value);
    } else {
        my $value1 = $self->xlfdProperties->get($propName);
        my $value2 = $self->properties->get($propName);
        if (defined $value1 && defined $value2) {
            # handle conflict later
        } elsif (defined $value1) {
            $self->properties->set($propName, $value);
        } elsif (defined $value2) {
            $self->xlfdProperties->set($propName, $value);
        }
    }
}

sub toString {
    my ($self, @args) = @_;
    my %options = (scalar @args == 1 && ref $args[0] eq 'HASH') ? %{$args[0]} : @args;
    my $result = sprintf("STARTFONT 2.2\n");
    foreach my $comment (@{$self->comments}) {
        if ($comment !~ m{^(?:$|\s)}) {
            $comment = " $comment";
        }
        $result .= sprintf("COMMENT%s\n", $comment);
    }
    if (defined $self->contentVersion) {
        $result .= sprintf("CONTENTVERSION %d\n", round($self->contentVersion));
    }
    if (defined $self->name) {
        $result .= sprintf("FONT %s\n", $self->name);
    }
    if (defined $self->pointSize ||
        defined $self->xResolution ||
        defined $self->yResolution) {
        $result .= sprintf("SIZE %d %d %d\n",
                           round($self->pointSize // 0),
                           round($self->xResolution // 0),
                           round($self->yResolution // 0));
    }
    if (defined $self->boundingBoxWidth ||
        defined $self->boundingBoxHeight ||
        defined $self->boundingBoxOffsetX ||
        defined $self->boundingBoxOffsetY) {
        $result .= sprintf("FONTBOUNDINGBOX %d %d %d %d\n",
                           round($self->boundingBoxWidth // 0),
                           round($self->boundingBoxHeight // 0),
                           round($self->boundingBoxOffsetX // 0),
                           round($self->boundingBoxOffsetY // 0));
    }
    if (defined $self->metricsSet) {
        $result .= sprintf("METRICSSET %d\n", round($self->metricsSet));
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
    if (defined $self->properties) {
        $result .= $self->properties->toString(@args);
    }
    my $count = scalar @{$self->glyphs};
    if ($count) {
        $result .= sprintf("CHARS %d\n", $count);
        foreach my $glyph (@{$self->glyphs}) {
            $result .= $glyph->toString(@args);
        }
    }
    $result .= "ENDFONT\n";
    return $result;
}

###############################################################################
# management of both versions of various properties:
# -   1: BDF font info
# -   2: BDF font properties

sub xResolution2 {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('RESOLUTION_X');
    }
    my $value = shift;
    $self->properties->setNumeric('RESOLUTION_X', $value);
}

sub yResolution2 {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('RESOLUTION_Y');
    }
    my $value = shift;
    $self->properties->setNumeric('RESOLUTION_Y', $value);
}

sub pointSize2 {                # returns or sets value in points
    my $self = shift;
    if (!scalar @_) {
        my $value = $self->properties->getNumeric('POINT_SIZE');
        $value /= 10 if defined $value;
        return $value;
    }
    my $value = shift;
    $value *= 10 if defined $value;
    $self->properties->setNumeric('POINT_SIZE', $value);
}

sub pixelSize {
    my $self = shift;
    if (!scalar @_) {
        return if !defined $self->pointSize;
        return if !defined $self->yResolution;
        return $self->pointSize / POINTS_PER_INCH * $self->yResolution;
    }
    if (!defined $self->yResolution) {
        die("setting pixelSize not supported unless yResolution is set\n");
    }
    my $value = shift;
    $value = $value * POINTS_PER_INCH / $self->yResolution;
    $self->pointSize($value);
}

sub pixelSize2 {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('PIXEL_SIZE');
    }
    my $value = shift;
    $self->properties->setNumeric('PIXEL_SIZE', $value);
}

sub ascent {
    my $self = shift;
    if (!scalar @_) {
        return unless defined $self->boundingBoxHeight;
        return unless defined $self->boundingBoxOffsetY;
        return $self->boundingBoxHeight + $self->boundingBoxOffsetY;
    }
    die("setting ascent not supported\n");
}

sub descent {
    my $self = shift;
    if (!scalar @_) {
        return unless defined $self->boundingBoxHeight;
        return unless defined $self->boundingBoxOffsetY;
        return $self->boundingBoxOffsetY * -1;
    }
    die("setting descent not supported\n");
}

sub ascent2 {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('FONT_ASCENT');
    }
    my $value = shift;
    $self->properties->setNumeric('FONT_ASCENT', $value);
}

sub descent2 {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('FONT_DESCENT');
    }
    my $value = shift;
    $self->properties->setNumeric('FONT_DESCENT', $value);
}

1;
