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

# Note: The ImageMagick commands in this script require
# larger-than-default resource limits.  In particular, in
# /etc/ImageMagick-6/policy.xml , I changed "memory" to 3GiB and "disk"
# to 5GiB.

# This script creates a directory for temporary storage as a
# subdirectory of the directory containing its .zip file argument.

# It may require adjusting the CONTRAST and MIDPOINT variables below.

# The output will be a tif file next to the input .zip.

if [ "$#" != "1" ]
then
    echo "Expected single argument (.zip file)" 1>&2
    exit 1
fi

DIR="$(dirname "$1")"
ZIPFILE="$(basename "$1")"

if ! echo "$ZIPFILE" | grep -q ".zip$"
then
    echo "Expected argument .zip file" 1>&2
    exit 1
fi

if [ ! -f "$DIR/$ZIPFILE" ]
then
    echo "Expected argument .zip file to exist" 1>&2
    exit 1
fi

FULL="$(echo -n "$ZIPFILE" | sed 's/.zip$//')"
BASE="$(echo -n "$FULL" | cut -d_ -f6-7)"
cd "$DIR" || exit $?
TMPDIR="$(mktemp -d ./tmpdir.XXXXXXXX)"
cd "$TMPDIR" || exit $?
B2PATH="$(unzip -qql "../$ZIPFILE" | grep "_B02.jp2" | head -1 | cut -b31-)"
B3PATH="$(echo $B2PATH | sed 's/_B02.jp2/_B03.jp2/')"
B4PATH="$(echo $B2PATH | sed 's/_B02.jp2/_B04.jp2/')"
unzip -j "../$ZIPFILE" "$B2PATH" "$B3PATH" "$B4PATH" || exit $?
B2JP2="$(basename "$B2PATH")"
B3JP2="$(basename "$B3PATH")"
B4JP2="$(basename "$B4PATH")"
gdal_translate "$B2JP2" B02.tif || exit $?
gdal_translate "$B3JP2" B03.tif || exit $?
gdal_translate "$B4JP2" B04.tif || exit $?
"rm" "$B2JP2" "$B3JP2" "$B4JP2"
gdalwarp -t_srs EPSG:3857 B02.tif B02-projected.tif || exit $?
gdalwarp -t_srs EPSG:3857 B03.tif B03-projected.tif || exit $?
gdalwarp -t_srs EPSG:3857 B04.tif B04-projected.tif || exit $?
"rm" B02.tif B03.tif B04.tif

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
mv RGB.tif "../${FULL}-RGB-${CONTRAST}x${MIDPOINT}.tif"

cd .. || exit $?
rmdir "$TMPDIR"
