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
    push(@{$self->{comments}}, $comment);
}

sub appendGlyph {
    my ($self, $glyph) = @_;
    push(@{$self->{glyphs}}, $glyph);
}

sub finalize {
    my ($self) = @_;
    foreach my $glyph (@{$self->glyphs}) {
        $glyph->finalize();
    }
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
        PIXEL_SIZE       => \&computePixelSize,
        POINT_SIZE       => \&computePointSize,
        RESOLUTION_X     => \&computeXResolution,
        RESOLUTION_Y     => \&computeYResolution,
        SPACING          => undef, # C, M, or P
        AVERAGE_WIDTH    => \&computeAverageWidth,
        CHARSET_REGISTRY => "ISO10646",
        CHARSET_ENCODING => "1",
        FONT_ASCENT      => sub { my ($self) = @_; return $self->computeFontAscentDescent('ascent'); },
        FONT_DESCENT     => sub { my ($self) = @_; return $self->computeFontAscentDescent('descent'); },
        DEFAULT_CHAR     => \&computeDefaultChar,
    );
}

sub computeAverageWidth {       # in tenths of pixels
    my ($self) = @_;
    my $glyphCount = scalar @{$self->glyphs};
    return if !$glyphCount;
    my $totalWidth = 0;
    foreach my $glyph (@{$self->glyphs}) {
        $totalWidth += $glyph->computeDWidthX();
    }
    return round($totalWidth / $glyphCount * 10);
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

    my $pointSize = $self->computePointSize();
    my $xResolution = $self->computeXResolution();
    my $yResolution = $self->computeYResolution();
    $result .= sprintf("SIZE %d %d %d\n",
                       round($pointSize / 10),
                       round($xResolution),
                       round($yResolution));
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
        my $properties = ref($self->properties)->from($self->properties);
        foreach my $propertyName (@DEFAULT_PROPERTY_NAMES) {
            my $value = $self->computePropertyValue($properties, $propertyName);
            if (!defined $value) {
                next;
            }
            $properties->set($propertyName, $value);
        }
        $result .= $properties->toString();
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

sub computeXResolution {
    my ($self) = @_;
    my $xRes1 = $self->xResolution;
    my $xRes2 = $self->properties->getNumeric('RESOLUTION_X');
    die("x resolutions inconsistent") if defined $xRes1 && defined $xRes2 && abs($xRes1 - $xRes2) > 0.1;
    die("x resolution not specified") if !defined $xRes1 && !defined $xRes2;
    return $xRes1 // $xRes2 // 96;
}
sub computeYResolution {
    my ($self) = @_;
    my $yRes1 = $self->yResolution;
    my $yRes2 = $self->properties->getNumeric('RESOLUTION_Y');
    die("y resolutions inconsistent") if defined $yRes1 && defined $yRes2 && abs($yRes1 - $yRes2) > 0.1;
    die("y resolution not specified") if !defined $yRes1 && !defined $yRes2;
    return $yRes1 // $yRes2 // 96;
}
sub computePixelSize {
    my ($self) = @_;
    my $pixelSize1 = $self->pixelSize;
    my $pixelSize2 = $self->properties->getNumeric('PIXEL_SIZE');
    die("pixel sizes inconsistent") if defined $pixelSize1 && defined $pixelSize2 && abs($pixelSize1 - $pixelSize2) > 0.01;
    if (!defined $pixelSize1 && !defined $pixelSize2) {
        my ($ascent, $descent) = $self->computeFontAscentDescent();
        if (defined $ascent && defined $descent) {
            return $ascent + $descent;
        }
    }
    return $pixelSize1 // $pixelSize2;
}
sub computePointSize {
    my ($self) = @_;
    my $pointSize1 = $self->pointSize;
    my $pointSize2 = $self->properties->getNumeric('POINT_SIZE'); # decipoints
    die("point sizes inconsistent") if defined $pointSize1 && defined $pointSize2 && round($pointSize1) != round($pointSize2 / 10);
    if (!defined $pointSize1 && !defined $pointSize2) {
        return 10 * $self->computePixelSize() * 72 / $self->computeYResolution();
    }
    return $pointSize1 * 10 if defined $pointSize1;
    return $pointSize2 if defined $pointSize2;
    return;
}
sub computeFontAscentDescent {
    my ($self, $idx) = @_;
    my ($ascent1, $descent1) = $self->computeFontAscentDescentBasedOnProperties();
    my ($ascent2, $descent2) = $self->computeFontAscentDescentBasedOnBoundingBox();
    my $ascent = $ascent1 // $ascent2;
    my $descent = $descent1 // $descent2;
    return $ascent if defined $idx && $idx eq 'ascent';
    return $descent if defined $idx && $idx eq 'descent';
    return ($ascent, $descent) if wantarray;
    return [$ascent, $descent];
}
sub computeFontAscentDescentBasedOnBoundingBox {
    my ($self) = @_;
    my $bbh = $self->{boundingBoxHeight};
    my $bby = $self->{boundingBoxOffsetY};
    return if !defined $bbh || !defined $bby;
    my $descent;
    my $ascent = $bbh + $bby;
    if ($bby <= 0) {
        $descent = -$bby;
    } else {
        $descent = 0;
    }
    return ($ascent, $descent) if wantarray;
    return [$ascent, $descent];
}
sub computeFontAscentDescentBasedOnProperties {
    my ($self) = @_;
    my $ascent = $self->properties->getNumeric('FONT_ASCENT');
    my $descent = $self->properties->getNumeric('FONT_DESCENT');
    return if (!defined $ascent || !defined $descent);
    ($ascent, $descent) = $self->recomputeFontAscentDescentNumbers($ascent, $descent);
    return ($ascent, $descent) if wantarray;
    return [$ascent, $descent];
}
sub recomputeFontAscentDescentNumbers {
    my ($self, $ascent, $descent) = @_;
    return if (!defined $ascent || !defined $descent);
    my $pixelSize = $self->computePixelSize();
    $ascent = round($ascent);
    $descent = round($descent);
    $pixelSize = round($pixelSize);
    my $cmp = ($ascent + $descent) - $pixelSize;
    if ($cmp < 0) {
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
    } elsif ($cmp > 0) {
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
    }
    return ($ascent, $descent) if wantarray;
    return [$ascent, $descent];
}
sub computePropertyValue {
    my ($self, $properties, $propertyName) = @_;
    my $value = $properties->get($propertyName);
    return $value if defined $value;
    my $defaultValue = $DEFAULT_PROPERTIES{$propertyName};
    if (!defined $defaultValue) {
        printf STDERR ("WARNING: %s: %s property SHOULD be specified; not setting.\n",
                       $self->filename,
                       $propertyName);
        return;
    }
    if (ref $defaultValue eq 'CODE') {
        my $newDefaultValue = $self->$defaultValue();
        if (!defined $newDefaultValue) {
            printf STDERR ("WARNING: %s: %s property SHOULD have been specified; cannot compute default.\n",
                           $self->filename,
                           $propertyName);
            return;
        }
        printf STDERR ("NOTICE: %s: %s property should have been specified; setting to %s\n",
                       $self->filename,
                       $propertyName,
                       $newDefaultValue);
        return $newDefaultValue;
    }
    if (ref $defaultValue eq '$CALCULATED') {
        printf STDERR ("WARNING: %s: %s property SHOULD have been CALCULATED; not setting.\n",
                       $self->filename,
                       $propertyName);
        return;
    }
    printf STDERR ("NOTICE: %s: %s property should have been specified; setting to %s\n",
                   $self->filename,
                   $propertyName,
                   $defaultValue);
    return $defaultValue;
}

1;
