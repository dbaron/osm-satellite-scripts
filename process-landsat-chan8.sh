#!/bin/bash

# from https://www.mapbox.com/tilemill/docs/guides/landsat-8-imagery/
# and based on ../../daxing/2016-08-08/*.sh

if [ "$#" != "1" ]
then
    echo "Expected single argument" 1>&2
    exit 1
fi

DIR="$(dirname "$1")"
TARGZ="$(basename "$1")"

if ! echo "$TARGZ" | grep -q ".tar.gz$"
then
    echo "Expected argument .tar.gz file" 1>&2
    exit 1
fi

if [ ! -f "$DIR/$TARGZ" ]
then
    echo "Expected argument .tar.gz file to exist" 1>&2
    exit 1
fi

BASE="$(echo -n "$TARGZ" | sed 's/.tar.gz$//')"
cd "$DIR"
tar xzvf "$TARGZ" "${BASE}_B8.TIF"
gdalwarp -t_srs EPSG:3857 "${BASE}_B8.TIF" temp-projected.tif
[ $? -eq 0 ] || exit $?
"rm" "${BASE}_B8.TIF"
CONTRAST=20   # try 10, 20, 50  (documentation says 0 none, 3 typical, 20 a lot)
MIDPOINT=16%  # try 12%, 16%
convert -sigmoidal-contrast "${CONTRAST}x${MIDPOINT}" temp-projected.tif temp-corrected.tif
[ $? -eq 0 ] || exit $?
convert -depth 8 temp-corrected.tif temp-8bit.tif
[ $? -eq 0 ] || exit $?
"rm" temp-corrected.tif
listgeo -tfw temp-projected.tif
[ $? -eq 0 ] || exit $?
"rm" temp-projected.tif
mv temp-projected.tfw temp-8bit.tfw
gdal_edit.py -a_srs EPSG:3857 temp-8bit.tif
[ $? -eq 0 ] || exit $?
"rm" temp-8bit.tfw
mv temp-8bit.tif "${BASE}_B8-processed-${CONTRAST}x${MIDPOINT}.tif"

# From http://www.imagemagick.org/script/command-line-options.php#sigmoidal-contrast
# 
# -sigmoidal-contrast contrastxmid-point
# 
# increase the contrast without saturating highlights or shadows.
# 
# Increase the contrast of the image using a sigmoidal transfer function without saturating highlights or shadows. Contrast indicates how much to increase the contrast. For example, 0 is none, 3 is typical and 20 is a lot.
# 
# The mid-point indicates where the maximum change 'slope' in contrast should fall in the resultant image (0 is white; 50% is middle-gray; 100% is black).
# 
# By default the image contrast is increased, use +sigmoidal-contrast to decrease the contrast.
# 
# To achieve the equivalent of a sigmoidal brightness change (similar to a gamma adjustment), you would use -sigmoidal-contrast {brightness}x0% to increase brightness and +sigmoidal-contrast {brightness}x0% to decrease brightness. Note the use of '0' fo rthe mid-point of the sigmoidal curve.
# 
# Using a very high contrast will produce a sort of 'smoothed thresholding' of the image. Not as sharp (with high aliasing effects) of a true threshold, but with tapered gray-levels around the threshold mid-point. 
