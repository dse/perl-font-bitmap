package Font::Bitmap::BDF::Parser;
use warnings;
use strict;

=head1 NAME

Font::Bitmap::BDF::Parser - parse a BDF file and build a Font::Bitmap::BDF object

=head1 SYNOPSIS

    $fh = ...;
    my $parser = Font::Bitmap::BDF::Parser->new();
    while (<$fh>) {
        $parser->parseLine($_);
    }
    $parser->eof();

    my $bdf = $parser->font;
    ...

=head1 DESCRIPTION

Parses the contents of an Adobe Bitmap Distribution Format file, line
by line.

Builds a Font::Bitmap::BDF object from it.

=head1 FORMAT EXTENSIONS

By default, certain extensions to BDF that facilitate the use of a
text editor are enabled.

=over 4

=item *

STARTCHAR

Normally the word STARTCHAR is followed by the glyph's name, in the
form of either one of the glyph names listed in the Adobe Glyph List
for New Fonts, or for Type 0 fonts, a numeric offset or glyph ID.

In order to facilitate editing, you may also follow STARTCHAR with a
glyph's Unicode codepoint in a hexadecimal format per one of the
following examples:

    STARTCHAR U+0031 <text>

    STARTCHAR 0x31 <text>

The contents of any additional text following the hexadecimal
codepoint are ignored.  You may use it to specify the character name,
but that is entirely an optional convention.

=item *

BITMAP

Normally each glyph's bitmap data is specified in the form of a
"BITMAP" line, followed by one or more lines containing hexademical
data, followed by an "ENDCHAR" line.

You can instead specify something like the following example:

    STARTCHAR U+006A LATIN SMALL LETTER J
    |    #  |
    |       |
    |   ##  |
    |    #  |
    |    #  |
    |    #  |
    + #  #  |
    |  ##   |
    ENDCHAR

Each line starts with a "|" or "+", followed by a series of spaces
or number signs ("#"), followed optionally by an "|" or "+".

Spaces are for pixels turned off, number signs ("#") are for pixels
turned on.  You may also use asterisks ("*") for pixels turned on.

A line starting "+" indicates that the bottom of its line of pixels is
the font's baseline.  In the above example, only the last line of
pixels is below the base line; the second-to-last row of pixels and
all preceding rows are above the baseline.

If there are any pixels to the left of the origin, as in the following
example:

    |      ###|
    |      ###|
    |      ###|
    |         |
    |     ### |
    |     ### |
    |     ### |
    |    ###  |
    |    ###  |
    |    ###  |
    |    ###  |
    |    ###  |
    |   ###   |
    +   ###   | <-- above the origin
    |   ###   | <-- below the origin
    |  ####   |
    | *###    |
    |**##     |
    |**#      |
    |--+------|

Add a line like the last line in the example above.  You may place it
above or below the bitmap data.  The COLUMN of pixels corresponding to
the "+" sign corresponds to the column on the right-hand side of the
origin; any preceding columns are to the left of the origin (shown as
"*" above).

=back

=head1 BUGS

Does not support vertical writing mode.

=cut

use Moo;

has state => (is => 'rw', default => 0);
has font => (
    is => 'rw', default => sub {
        my ($self) = @_;
        return Font::Bitmap::BDF->new(parser => $self);
    }
);
has glyph => (is => 'rw');
has lineNumber => (is => 'rw', default => 0);
has enableExtensions => (is => 'rw', default => 1);
has filename => (is => 'rw');

has xResolution => (is => 'rw');
has yResolution => (is => 'rw');
sub resolution {
    my $self = shift;
    if (scalar @_) {
        my ($x, $y) = @_;
        $y //= $x;
        if (!defined $self->xResolution) {
            $self->xResolution($x);
        }
        if (!defined $self->yResolution) {
            $self->yResolution($y);
        }
    }
}

our %RE;
BEGIN {
    $RE{real} = qr{(?:[-+]?(?:(?=[.]?[0-9])(?:[0-9]*)(?:\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?)}x;
    $RE{endWord} = qr{(?=$|\s)};
    $RE{word} = qr{(?:\S+)};
    $RE{string} = qr{(?:\S.*?)};
}

use Font::Bitmap::BDF;

use File::Basename qw(dirname);

sub parseLine {
    my ($self, $line) = @_;
    $self->lineNumber($self->lineNumber + 1);
    $line =~ s{\R\z}{};         # safer than chomp.
    if ($line =~ m{^\s*include\s+(?<filename>\S.*?)\s*$}xi) {
        # include <filename>
        #     at any point includes the contents of <filename>
        $self->include($+{filename});
    } elsif ($self->state == 0) {
        $self->parseLineState0($line);
    } elsif ($self->state == 1) {
        $self->parseLineState1($line);
    } elsif ($self->state == 2) {
        $self->parseLineState2($line);
    } elsif ($self->state == 3) {
        $self->parseLineState3($line);
    } elsif ($self->state == 4) {
        $self->parseLineState4($line);
    }
}

sub include {
    my ($self, $filename) = @_;
    my $fh;

    my $alsoTryFilename;
    if (defined $self->filename) {
        $alsoTryFilename = dirname($self->filename) . '/' . $filename;
    }

    if (!open($fh, '<', $filename)) {
        my $error1 = "cannot read $filename: $!\n";
        if (defined $alsoTryFilename) {
            if (!open($fh, '<', $alsoTryFilename)) {
                warn($error1);
                die("cannot read $alsoTryFilename: $!\n");
            }
        } else {
            die("cannot read $filename: $!\n");
        }
    }
    while (<$fh>) {
        $self->parseLine($_);
    }
}

# while reading main BDF data
#
sub parseLineState0 {
    my ($self, $line) = @_;
    if ($line =~ m{^\s* STARTFONT
                   \s+ (?<formatVersion>$RE{string}) \s*$}xi) {
        $self->font->formatVersion($1);
    } elsif ($line =~ m{^\s* COMMENT $RE{endWord}
                        (?<comment>.*)$}xi) {
        $self->font->appendComment($+{comment} // '');
    } elsif ($line =~ m{^\s* CONTENTVERSION
                        \s+ (?<contentVersion>$RE{real})}xi) {
        $self->font->contentVersion($+{contentVersion});
    } elsif ($line =~ m{^\s* FONT
                        \s+ (?<fontName>$RE{string}) \s*$}xi) {
        $self->font->name($+{fontName});
    } elsif ($line =~ m{^\s* SIZE
                        \s+ (?<pointSize>$RE{real})
                        \s+ (?<xResolution>$RE{real})
                        \s+ (?<yResolution>$RE{real})}xi) {
        $self->font->pointSize($+{pointSize});
        $self->font->xResolution($+{xResolution});
        $self->font->yResolution($+{yResolution});
    } elsif ($line =~ m{^\s* FONTBOUNDINGBOX
                        \s+ (?<width>$RE{real})
                        \s+ (?<height>$RE{real})
                        \s+ (?<offsetX>$RE{real})
                        \s+ (?<offsetY>$RE{real})}xi) {
        $self->font->boundingBoxWidth($+{width});
        $self->font->boundingBoxHeight($+{height});
        $self->font->boundingBoxOffsetX($+{offsetX});
        $self->font->boundingBoxOffsetY($+{offsetY});
    } elsif ($line =~ m{^\s* METRICSSET
                        \s+ (?<metricsSet>$RE{real})}xi) {
        $self->font->metricsSet($+{metricsSet});
    } elsif ($line =~ m{^\s* SWIDTH
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->font->sWidthX($+{x});
        $self->font->sWidthY($+{y});
    } elsif ($line =~ m{^\s* DWIDTH
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->font->dWidthX($+{x});
        $self->font->dWidthY($+{y});
    } elsif ($line =~ m{^\s* SWIDTH1
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->font->sWidth1X($+{x});
        $self->font->sWidth1Y($+{y});
    } elsif ($line =~ m{^\s* DWIDTH1
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->font->dWidth1X($+{x});
        $self->font->dWidth1Y($+{y});
    } elsif ($line =~ m{^\s* VVECTOR
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->font->vVectorX($+{x});
        $self->font->vVectorY($+{y});
    } elsif ($line =~ m{^\s* STARTPROPERTIES $RE{endWord}}xi) {
        $self->state(1);
    } elsif ($line =~ m{^\s* CHARS $RE{endWord}}xi) {
        $self->state(2);
    } elsif ($line =~ m{^\s* STARTCHAR
                        \s+ (?<name>$RE{string}) \s*$}xi) {
        $self->endChar();
        $self->glyph(Font::Bitmap::BDF::Glyph->new(font => $self->font,
                                                   name => $+{name}));
        $self->font->appendGlyph($self->glyph);
        $self->state(3);
    } elsif ($line =~ m{^\s* ENDFONT $RE{endWord}}xi) {
        $self->endFont();
        $self->state(-1);
    }
}

# while reading bdf property data between STARTPROPERTIES and
# ENDPROPERTIES lines
#
sub parseLineState1 {
    my ($self, $line) = @_;
    if ($line =~ m{^\s* ENDPROPERTIES $RE{endWord}}xi) {
        $self->state(0);
    } elsif ($line =~ m{^\s* (?<name>$RE{word})
                        \s+ (?<value>$RE{string}) \s*$}xi) {
        $self->font->properties->append($+{name}, $+{value});
    } elsif ($line =~ m{^\s* ENDFONT $RE{endWord}}xi) {
        $self->endFont();
        $self->state(-1);
    }
}

# while in the character data section of the BDF file but not
# yet reading a character.
#
sub parseLineState2 {
    my ($self, $line) = @_;
    if ($line =~ m{^\s* STARTCHAR
                   \s+ (?<name>$RE{string}) \s*$}xi) {
        $self->endChar();
        $self->glyph(Font::Bitmap::BDF::Glyph->new(font => $self->font,
                                                   name => $+{name}));
        $self->font->appendGlyph($self->glyph);
        $self->state(3);
    } elsif ($line =~ m{^\s* ENDFONT $RE{endWord}}xi) {
        $self->endFont();
        $self->state(-1);
    }
}

# while reading info for a glyph
#
sub parseLineState3 {
    my ($self, $line) = @_;
    if ($line =~ m{^\s* ENCODING
                   \s+ (?<encoding>$RE{real})
                   (?: \s+ (?<nonStandardEncoding>$RE{real}) )?}xi) {
        $self->glyph->encoding($+{encoding});
        if (defined $+{nonStandardEncoding}) {
            $self->glyph->nonStandardEncoding($+{nonStandardEncoding})
        }
    } elsif ($line =~ m{^\s* SWIDTH
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->glyph->sWidthX($+{x});
        $self->glyph->sWidthY($+{y});
    } elsif ($line =~ m{^\s* DWIDTH
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->glyph->dWidthX($+{x});
        $self->glyph->dWidthY($+{y});
    } elsif ($line =~ m{^\s* SWIDTH1
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->glyph->sWidth1X($+{x});
        $self->glyph->sWidth1Y($+{y});
    } elsif ($line =~ m{^\s* DWIDTH1
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->glyph->dWidth1X($+{x});
        $self->glyph->dWidth1Y($+{y});
    } elsif ($line =~ m{^\s* VVECTOR
                        \s+ (?<x>$RE{real})
                        \s+ (?<y>$RE{real})}xi) {
        $self->glyph->vVectorX($+{x});
        $self->glyph->vVectorY($+{y});
    } elsif ($line =~ m{^\s* BBX
                        \s+ (?<width>$RE{real})
                        \s+ (?<height>$RE{real})
                        \s+ (?<offsetX>$RE{real})
                        \s+ (?<offsetY>$RE{real})}xi) {
        $self->glyph->boundingBoxWidth($+{width});
        $self->glyph->boundingBoxHeight($+{height});
        $self->glyph->boundingBoxOffsetX($+{offsetX});
        $self->glyph->boundingBoxOffsetY($+{offsetY});
    } elsif ($line =~ m{^\s* BITMAP $RE{endWord}}xi) {
        $self->state(4);
    } elsif ($line =~ m{^\s* ENDCHAR $RE{endWord}}xi) {
        $self->endChar();
        $self->state(2);
    } elsif ($line =~ m{^\s* ENDFONT $RE{endWord}}xi) {
        $self->endFont();
        $self->state(-1);
    } elsif ($self->enableExtensions &&
             $line =~ m{^\s*
                        (?<startMarker>[+|])
                        (?<data>[ *#]*?)
                        (?<endMarker>[+|])?
                        \s*$}xi) {
        $self->glyph->appendBitmapData({
            format      => 'dots',
            startMarker => $+{startMarker},
            dots        => $+{data},
            endMarker   => $+{endMarker},
        });
        $self->state(4);
    }
}

# while reading glyph bitmap data
#
sub parseLineState4 {
    my ($self, $line) = @_;
    if ($line =~ m{^\s* ENDCHAR $RE{endWord}}xi) {
        $self->endChar();
        $self->state(2);
    } elsif ($line =~ m{^\s* ENDFONT $RE{endWord}}xi) {
        $self->endFont();
        $self->state(-1);
    } elsif ($line =~ m{^\s* (?<data>[A-Za-z0-9]+)}xi) {
        $self->glyph->appendBitmapData({
            format => 'hex',
            hex    => $+{data}
        });
    } elsif ($self->enableExtensions &&
             $line =~ m{^\s*
                        \|
                        (?<negativeLeftOffset>-*)\+-*
                        \|?
                        \s*$}xi) {
        $self->glyph->negativeLeftOffset(length($+{negativeLeftOffset}));
    } elsif ($self->enableExtensions &&
             $line =~ m{^\s*
                        (?<startMarker>[+|])
                        (?<data>[ *#]*?)
                        (?<endMarker>[+|])?
                        \s*$}xi) {
        $self->glyph->appendBitmapData({
            format      => 'dots',
            startMarker => $+{startMarker},
            dots        => $+{data},
            endMarker   => $+{endMarker},
        });
    }
}

sub endChar {
    my ($self) = @_;
    if (defined $self->glyph) {
        $self->glyph->finalize();
        $self->glyph(undef);
    }
}

sub endFont {
    my ($self) = @_;
    $self->endChar();
    $self->font->finalize();
    if (!defined $self->font->xResolution) {
        if (defined $self->xResolution) {
            $self->font->xResolution($self->xResolution);
        }
    }
    if (!defined $self->font->yResolution) {
        if (defined $self->yResolution) {
            $self->font->yResolution($self->yResolution);
        }
    }
}

sub eof {
    my ($self) = @_;
    $self->endFont();
}

1;
