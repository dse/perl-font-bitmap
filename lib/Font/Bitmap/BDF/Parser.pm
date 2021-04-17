package Font::Bitmap::BDF::Parser;
use warnings;
use strict;

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
