package Font::Bitmap::BDF::Constants;
use warnings;
use strict;

use base 'Exporter';

our @EXPORT = qw();
our @EXPORT_OK = qw(POINTS_PER_INCH);
our %EXPORT_TAGS = (
    'all' => [qw(POINTS_PER_INCH)]
);

use constant POINTS_PER_INCH => 72;

1;
