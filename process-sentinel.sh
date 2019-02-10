#!/bin/bash

# Copyright 2018 L. David Baron
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Script for processing Sentinel-2 imagery (MSI, Level 1-C) from
# https://scihub.copernicus.eu/dhus/ into something that can be uploaded
# to MapBox studio.

# This depends on ImageMagick, gdal, and geotiff.  If you don't have the
# dependencies, you might be able to get them by doing something like:
#   on Ubuntu:
#     # sudo apt install geotiff-bin gdal-bin imagemagick
#   on Mac OS X:
#     # brew install imagemagick
#     # brew install libgeotiff
# For more information, see:
#   https://www.imagemagick.org/
#   https://www.gdal.org/
#   https://trac.osgeo.org/geotiff/

# Note: The ImageMagick commands in this script require
# larger-than-default resource limits.  In particular, in
# /etc/ImageMagick-6/policy.xml , I changed "memory" to 3GiB and "disk"
# to 5GiB.  (This was needed on Ubuntu but not on Mac OS X.)

# This script creates a directory for temporary storage as a
# subdirectory of the directory containing its .zip file argument(s).

# It may require adjusting the CONTRAST and MIDPOINT variables below.

# The output will be a tif file next to the input .zip.

if [ $# -lt 1 ]
then
    echo "Expected argument(s) (.zip file(s))" 1>&2
    exit 1
fi

for ((i = 1; $i <= $#; i=$i + 1))
do
    ZIPFILE="${!i}"
    if ! echo "$ZIPFILE" | grep -q ".zip$"
    then
        echo "Expected argument .zip file" 1>&2
        exit 1
    fi

    if [ ! -f "$ZIPFILE" ]
    then
        echo "Expected argument .zip file to exist" 1>&2
        exit 1
    fi
done

TMPDIR="$(mktemp -d "$(dirname "$1")"/tmpdir.XXXXXXXX)"

FULL=""
B2FILES=""
B3FILES=""
B4FILES=""

for ((i = 1; $i <= $#; i=$i + 1))
do
    ZIPFILE="${!i}"
    FULL="$FULL$(basename "$ZIPFILE" | sed 's/.zip$//')-"

    B2PATH="$(unzip -qql "$ZIPFILE" | grep "_B02.jp2" | head -1 | cut -b31-)"
    B3PATH="$(echo $B2PATH | sed 's/_B02.jp2/_B03.jp2/')"
    B4PATH="$(echo $B2PATH | sed 's/_B02.jp2/_B04.jp2/')"
    unzip -j "$ZIPFILE" "$B2PATH" "$B3PATH" "$B4PATH" -d "$TMPDIR" || exit $?
    B2JP2="$(basename "$B2PATH")"
    B3JP2="$(basename "$B3PATH")"
    B4JP2="$(basename "$B4PATH")"
    gdal_translate "$TMPDIR/$B2JP2" "$TMPDIR/B02-$i.tif" || exit $?
    B2FILES="$B2FILES B02-$i.tif"
    "rm" "$TMPDIR/$B2JP2"
    gdal_translate "$TMPDIR/$B3JP2" "$TMPDIR/B03-$i.tif" || exit $?
    B3FILES="$B3FILES B03-$i.tif"
    "rm" "$TMPDIR/$B3JP2"
    gdal_translate "$TMPDIR/$B4JP2" "$TMPDIR/B04-$i.tif" || exit $?
    B4FILES="$B4FILES B04-$i.tif"
    "rm" "$TMPDIR/$B4JP2"
done

cd "$TMPDIR" || exit $?

gdalwarp -t_srs EPSG:3857 $B2FILES B02-projected.tif || exit $?
"rm" $B2FILES
gdalwarp -t_srs EPSG:3857 $B3FILES B03-projected.tif || exit $?
"rm" $B3FILES
gdalwarp -t_srs EPSG:3857 $B4FILES B04-projected.tif || exit $?
"rm" $B4FILES

listgeo -tfw B02-projected.tif || exit $?
mv B02-projected.tfw RGB.tfw || exit $?

CONTRAST=80  # try 80 (documentation says 0 none, 3 typical, 20 a lot)
MIDPOINT=1%  # try 1%
convert -sigmoidal-contrast "${CONTRAST}x${MIDPOINT}" B02-projected.tif B02-corrected.tif || exit $?
convert -sigmoidal-contrast "${CONTRAST}x${MIDPOINT}" B03-projected.tif B03-corrected.tif || exit $?
convert -sigmoidal-contrast "${CONTRAST}x${MIDPOINT}" B04-projected.tif B04-corrected.tif || exit $?
"rm" B02-projected.tif B03-projected.tif B04-projected.tif

convert -depth 8 B02-corrected.tif B02-8bit.tif || exit $?
convert -depth 8 B03-corrected.tif B03-8bit.tif || exit $?
convert -depth 8 B04-corrected.tif B04-8bit.tif || exit $?
"rm" B02-corrected.tif B03-corrected.tif B04-corrected.tif

convert B0{4,3,2}-8bit.tif -combine RGB.tif || exit $?
"rm" B02-8bit.tif B03-8bit.tif B04-8bit.tif
gdal_edit.py -a_srs EPSG:3857 RGB.tif || exit $?
"rm" RGB.tfw
mv RGB.tif "../${FULL}RGB-${CONTRAST}x${MIDPOINT}.tif"

cd .. || exit $?
rmdir "$TMPDIR"
