package Font::Bitmap::BDF;
use warnings;
use strict;

use lib "../..";
use Mooo;

sub new {
    my ($class, %args) = @_;
    my $self = bless({}, $class);
    $self->init(%args);
    return $self;
}

has filename       => (is => 'rw', default => '-');
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
has guess => (is => 'rw', default => 0);

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

has glyphs => (is => 'rw', default => sub { return []; });

has parser => (is => 'rw');

has properties => (
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

    # $xxx1 variables come from top level font information.  Generally
    # we favor these over $xxx2 variables, which see below.
    my $pixelSize1 = $self->pixelSize;
    my $pointSize1 = $self->pointSize;
    my $xRes1 = $self->xResolution;
    my $yRes1 = $self->yResolution;

    # $xxx2 variables come from the font properties section.
    my $pixelSize2 = $self->properties->getNumeric('PIXEL_SIZE');
    my $pointSize2 = $self->properties->getNumeric('POINT_SIZE');
    my $xRes2      = $self->properties->getNumeric('RESOLUTION_X');
    my $yRes2      = $self->properties->getNumeric('RESOLUTION_Y');
    my $ascent2    = $self->properties->getNumeric('FONT_ASCENT');
    my $descent2   = $self->properties->getNumeric('FONT_DESCENT');

    if (!defined $xRes1 && !defined $xRes2) {
        die("no x resolution specified\n");
    }
    if (defined $xRes1 && defined $xRes2 && $xRes1 != $xRes2) {
        die("x resolutions differ\n");
    }

    if (!defined $yRes1 && !defined $yRes2) {
        die("no y resolution specified\n");
    }
    if (defined $yRes1 && defined $yRes2 && $yRes1 != $yRes2) {
        die("y resolutions differ\n");
    }

    if (!defined $pixelSize1 && !defined $pixelSize2) {
        die("no pixel size specified\n");
    }
    if (defined $pixelSize1 && defined $pixelSize2 && $pixelSize1 != $pixelSize2) {
        die("pixel sizes differ\n");
    }

    if (defined $pointSize1 && defined $pointSize2 && $pointSize1 != round($pointSize2 / 10)) {
        die("point sizes differ\n");
    }
    if (!defined $pointSize1 && !defined $pointSize2) {
        $pointSize1 = ($pixelSize1 // $pixelSize2) * 72 / ($yRes1 // $yRes2 // 96);
        $pointSize2 = $pointSize1;
    }

    my $xRes = $xRes1 // $xRes2;
    my $yRes = $yRes1 // $yRes2;

    my $pixelSize = $pixelSize1 // $pixelSize2;

    # we round this later.
    my $pointSize =
      (defined $pointSize1) ? $pointSize1 :
      (defined $pointSize2) ? ($pointSize2 / 10) : undef;

    # "Guess" initial values of ascent and descent from font bounding
    # box
    my $ascent1;
    my $descent1;
    my $bbw = $self->boundingBoxWidth;
    my $bbh = $self->boundingBoxHeight;
    my $bbx = $self->boundingBoxOffsetX;
    my $bby = $self->boundingBoxOffsetY;
    if (defined $bbh && defined $bby) {
        $ascent1 = $bbh + $bby;
        if ($bby <= 0) {
            $descent1 = -$bby;
        } else {
            $descent1 = 0;
        }
    }

    # Derived implicitly from font info.
    ($ascent1, $descent1) = recomputeAscentDescent($ascent1, $descent1);

    # Specified explicitly as FONT_{ASCENT,DESCENT} properties.
    ($ascent2, $descent2) = recomputeAscentDescent($ascent2, $descent2);

    # Favor what's explicitly specified over what's derived implicitly
    # if they differ.
    my $ascent  = $ascent2 // $ascent1;
    my $descent = $descent2 // $descent1;

    $self->pixelSize($pixelSize) if defined $pixelSize;
    $self->pointSize(round($pointSize)) if defined $pointSize;
    $self->xResolution($xRes) if defined $xRes;
    $self->yResolution($yRes) if defined $yRes;

    $self->properties->setNumeric('PIXEL_SIZE', $pixelSize) if defined $pixelSize;
    $self->properties->setNumeric('POINT_SIZE', round($pointSize * 10)) if defined $pointSize;
    $self->properties->setNumeric('RESOLUTION_X', $xRes) if defined $xRes;
    $self->properties->setNumeric('RESOLUTION_Y', $yRes) if defined $yRes;
    $self->properties->setNumeric('FONT_ASCENT', $ascent) if defined $ascent;
    $self->properties->setNumeric('FONT_DESCENT', $descent) if defined $descent;

    foreach my $glyph (@{$self->glyphs}) {
        $glyph->finalize();
    }

    $self->finalizeProperties();
}

our @DEFAULT_PROPERTY_NAMES;
our %DEFAULT_PROPERTIES;
BEGIN {
    @DEFAULT_PROPERTY_NAMES = (
        "FOUNDRY",
        "FAMILY_NAME",
        "WEIGHT_NAME",
        "SLANT",
        "SETWIDTH_NAME",
        "ADD_STYLE_NAME",
        "PIXEL_SIZE",
        "POINT_SIZE",
        "RESOLUTION_X",
        "RESOLUTION_Y",
        "SPACING",
        "AVERAGE_WIDTH",
        "CHARSET_REGISTRY",
        "CHARSET_ENCODING",
        "FONT_ASCENT",
        "FONT_DESCENT",
        "DEFAULT_CHAR",
    );
    %DEFAULT_PROPERTIES = (
        FOUNDRY          => undef,
        FAMILY_NAME      => undef,
        WEIGHT_NAME      => undef, # usually Bold or Medium
        SLANT            => undef, # usually I, O, or R
        SETWIDTH_NAME    => "Normal",
        ADD_STYLE_NAME   => "",
        PIXEL_SIZE       => '$CALCULATED',
        POINT_SIZE       => '$CALCULATED',
        RESOLUTION_X     => '$CALCULATED',
        RESOLUTION_Y     => '$CALCULATED',
        SPACING          => undef, # C, M, or P
        AVERAGE_WIDTH    => \&computeAverageWidth,
        CHARSET_REGISTRY => "ISO10646",
        CHARSET_ENCODING => "1",
        FONT_ASCENT      => '$CALCULATED',
        FONT_DESCENT     => '$CALCULATED',
        DEFAULT_CHAR     => \&computeDefaultChar,
    );
}

sub finalizeProperties {
    my ($self) = @_;
    foreach my $propertyName (@DEFAULT_PROPERTY_NAMES) {
        my $value = $self->properties->get($propertyName);
        next if defined $value;

        my $defaultValue = $DEFAULT_PROPERTIES{$propertyName};
        if (!defined $defaultValue) {
            printf STDERR ("WARNING: %s: %s property SHOULD be specified; not setting.\n",
                           $self->filename,
                           $propertyName);
        }

        if (ref $defaultValue eq 'CODE') {
            my $newDefaultValue = $self->$defaultValue();
            if (!defined $newDefaultValue) {
                printf STDERR ("WARNING: %s: %s property SHOULD have been specified; cannot compute default.\n",
                               $self->filename,
                               $propertyName);
                next;
            }
            printf STDERR ("NOTICE: %s: %s property should have been specified; setting to %s\n",
                           $self->filename,
                           $propertyName,
                           $newDefaultValue);
            $self->properties->set($propertyName, $newDefaultValue);
            next;
        }

        if (ref $defaultValue eq '$CALCULATED') {
            printf STDERR ("WARNING: %s: %s property SHOULD have been CALCULATED; not setting.\n",
                           $self->filename,
                           $propertyName);
            next;
        }

        printf STDERR ("NOTICE: %s: %s property should have been specified; setting to %s\n",
                       $self->filename,
                       $propertyName,
                       $defaultValue);
        $self->properties->set($propertyName, $defaultValue);
    }
}

sub computeAverageWidth {
    my ($self) = @_;
    my $glyphCount = scalar @{$self->glyphs};
    return if !$glyphCount;
    my $totalWidth = 0;
    foreach my $glyph (@{$self->glyphs}) {
        $totalWidth += $glyph->dWidthX;
    }
    return round($totalWidth / $glyphCount);
}

sub computeDefaultChar {
    my ($self) = @_;

    # U+0020 SPACE
    if (grep { $_->encoding == 32 } @{$self->glyphs}) {
        return 32;
    }

    # U+0000 <Null>
    if (grep { $_->encoding == 0 } @{$self->glyphs}) {
        return 0;
    }

    # U+FFFD REPLACEMENT CHARACTER
    if (grep { $_->encoding == 0xfffd } @{$self->glyphs}) {
        return 0xfffd;
    }

    return;
}

sub guessAscentAndDescent {
    my ($self) = @_;
    my $bbHeight = $self->boundingBoxHeight // 0;
    my $bbOffset = $self->boundingBoxOffsetY // 0;
    if (!defined $self->ascentProperty) {
        $self->ascentProperty($bbHeight + $bbOffset);
    }
    if (!defined $self->descentProperty) {
        if ($bbOffset < 0) {
            $self->descentProperty(-$bbOffset);
        } else {
            $self->descentProperty(0);
        }
    }
}

sub guessPixelSize {
    my ($self) = @_;
    warn("guessing pixel size...\n");
    if (defined $self->ascent && defined $self->descent) {
        warn("ascent is ", $self->ascent, "\n");
        warn("descent is ", $self->descent, "\n");
        my $height = $self->ascent + $self->descent;
        if (!defined $self->pixelSize) {
            $self->pixelSize($height);
            warn("setting pixel size to ", $self->pixelSize, "\n");
        }
        if (!defined $self->pixelSizeProperty) {
            $self->pixelSizeProperty($height);
            warn("setting pixel size property to ", $self->pixelSizeProperty, "\n");
        }
    }
}

sub matchAscentAndDescent {
    my ($self) = @_;
    if (defined $self->ascent && !defined $self->ascentProperty) {
        $self->ascentProperty($self->ascent);
    }
    if (defined $self->descent && !defined $self->descentProperty) {
        $self->descentProperty($self->descent);
    }
}

sub matchResolutions {
    my ($self) = @_;
    if (!defined $self->xResolution && defined $self->xResolutionProperty) {
        $self->xResolution($self->xResolutionProperty)
    }
    if (!defined $self->xResolutionProperty && defined $self->xResolution) {
        $self->xResolutionProperty($self->xResolution)
    }
    if (!defined $self->yResolution && defined $self->yResolutionProperty) {
        $self->yResolution($self->yResolutionProperty)
    }
    if (!defined $self->yResolutionProperty && defined $self->yResolution) {
        $self->yResolutionProperty($self->yResolution)
    }
}

sub matchPixelAndPointSizes {
    my ($self) = @_;
    if (!defined $self->pointSize && defined $self->pointSizeProperty) {
        $self->pointSize($self->pointSizeProperty);
    }
    if (!defined $self->pointSizeProperty && defined $self->pointSize) {
        $self->pointSizeProperty($self->pointSize);
    }
    if (!defined $self->pixelSize && defined $self->pixelSizeProperty) {
        $self->pixelSize($self->pixelSizeProperty);
    }
    if (!defined $self->pixelSizeProperty && defined $self->pixelSize) {
        $self->pixelSizeProperty($self->pixelSize);
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
    if (defined $self->pointSize &&
        defined $self->xResolution &&
        defined $self->yResolution) {
        $result .= sprintf("SIZE %d %d %d\n",
                           round($self->pointSize // 0),
                           round($self->xResolution // 0),
                           round($self->yResolution // 0));
    }
    if (defined $self->boundingBoxWidth &&
        defined $self->boundingBoxHeight &&
        defined $self->boundingBoxOffsetX &&
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

sub xResolutionProperty {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('RESOLUTION_X');
    }
    my $value = shift;
    $self->properties->setNumeric('RESOLUTION_X', round($value));
}

sub yResolutionProperty {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('RESOLUTION_Y');
    }
    my $value = shift;
    $self->properties->setNumeric('RESOLUTION_Y', round($value));
}

sub pointSizeProperty {                # returns or sets value in points
    my $self = shift;
    if (!scalar @_) {
        my $value = $self->properties->getNumeric('POINT_SIZE');
        $value /= 10 if defined $value;
        return $value;
    }
    my $value = shift;
    $value *= 10 if defined $value;
    $self->properties->setNumeric('POINT_SIZE', round($value));
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

sub pixelSizeProperty {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('PIXEL_SIZE');
    }
    my $value = shift;
    $self->properties->setNumeric('PIXEL_SIZE', round($value));
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

sub ascentProperty {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('FONT_ASCENT');
    }
    my $value = shift;
    $self->properties->setNumeric('FONT_ASCENT', round($value));
}

sub descentProperty {
    my $self = shift;
    if (!scalar @_) {
        return $self->properties->getNumeric('FONT_DESCENT');
    }
    my $value = shift;
    $self->properties->setNumeric('FONT_DESCENT', round($value));
}

# For when ascent + descent != pixel size...
our $FAVOR_ASCENT;              # 1 = favor ascent; 0 = favor descent
BEGIN {
    $FAVOR_ASCENT = 0;
}

# Ascent + descent must be pixel size to silence a fontforge
# warning.
sub recomputeAscentDescent {
    my ($ascent, $descent, $pixelSize) = @_;
    if (!defined $ascent) { return; }
    if (!defined $descent) { return; }
    if (!defined $pixelSize) { return ($ascent, $descent); }
    $ascent = round($ascent);
    $descent = round($descent);
    $pixelSize = round($pixelSize);
    my $cmp = ($ascent + $descent) - $pixelSize;
    # < 0 means asc+desc < px; > 0 means asc+desc > px
    if ($cmp == 0) {
        return ($ascent, $descent);
    } elsif ($cmp < 0) {
        my $addBoth = -$cmp;    # positive
        my $addAscent;
        my $addDescent;
        if ($FAVOR_ASCENT) {
            $addDescent = floor($addBoth / 2);
            $addAscent = $addBoth - $addDescent;
        } else {
            $addAscent = floor($addBoth / 2);
            $addDescent = $addBoth - $addAscent;
        }
        $ascent += $addAscent;
        $descent += $addDescent;
        return ($ascent, $descent);
    } else {
        my $subtractBoth = $cmp; # positive
        my $subtractDescent;
        my $subtractAscent;
        if ($FAVOR_ASCENT) {
            $subtractAscent = floor($subtractBoth / 2);
            $subtractDescent = $subtractBoth - $subtractAscent;
        } else {
            $subtractDescent = floor($subtractBoth / 2);
            $subtractAscent = $subtractBoth - $subtractDescent;
        }
        $ascent -= $subtractAscent;
        $descent -= $subtractDescent;
        return ($ascent, $descent);
    }
}

# In case we ever need to convert between pixel sizes and scalable
# WIDTH units:
#
# <swidth> is the scalable width in units of 1/1000 the size of the
# glyph.
#
# <pxsize> is the font's vertical pixel size.
# <ptsize> is the font's vertical point size.
# <ptwidth> is the width in points.
# <pxwidth> is the width in pixels.
#
# <ptwidth> = <swidth> / 1000 * <ptsize>
# <pxwidth> = <ptwidth> / 72 * <xres>
# <ptwidth> = <pxwidth> * <xres> / 72
# <swidth> = <ptwidth> / <ptsize> * 1000
#
# Conversion between HEIGHT units:
#
# <pxsize> = <ptsize> / 72 * <yres>
# <ptsize> = <pxsize> / <yres> * 72

1;
