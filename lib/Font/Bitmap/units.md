In case we ever need to convert between pixel sizes and scalable
WIDTH units:

    <swidth> is the scalable width in units of 1/1000 the size of the
    glyph.

    <pxsize> is the font's vertical pixel size.
    <ptsize> is the font's vertical point size.
    <ptwidth> is the width in points.
    <pxwidth> is the width in pixels.

    <ptwidth> = <swidth> / 1000 * <ptsize>
    <pxwidth> = <ptwidth> / 72 * <xres>
    <ptwidth> = <pxwidth> * <xres> / 72
    <swidth> = <ptwidth> / <ptsize> * 1000

Conversion between HEIGHT units:

    <pxsize> = <ptsize> / 72 * <yres>
    <ptsize> = <pxsize> / <yres> * 72

