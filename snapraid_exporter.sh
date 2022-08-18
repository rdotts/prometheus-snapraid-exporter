#!/bin/bash
#----------------------------------------------------------------------------
# Created By: Ryan Dotts
# Created Date: Aug 17 2022
# email: ryan@dotts.net
# ---------------------------------------------------------------------------
# Simple bash script to gather stats from a snapraid array and push them to prometheus.
# Pushing seemed like a better option than a scrape endpoint since (1) snapraid status
# takes several seconds to run, at least on my system (2) if your data is
# changing constantly, snapraid probably isn't the best solution, and
# (3) you can't get the status during scrubs and syncs anyway.
# ---------------------------------------------------------------------------

# TODO: Arguments/env variables for prometheus url, username, pass, etc.

if [ "$UID" -ne "0" ]; then
  echo "Error: collector must be run as root. Running with uid: $UID"
  exit 1
fi

if [ -z "$(which snapraid)" ]; then
  echo "Error: Could not find snapraid binary. Make sure snapraid is available from $PATH"
  exit 1
fi


# Extract the data table from the output of the snapraid status command and format it by removing extra spaces, replacing
# - with 0.0, and removing the percent symbol. Also removed the decimal from wasted bytes to avoid floating point math
# in bash, and the negative sign from  wasted bytes (who even put that there?  isn't negative wasted space a double
# negative?) Grabs all lines, including the totals from the final line of the table
# which notably has no device name.
# TODO: Append device name for entire array, e.g. snapraid-entire-array
SNAPRAID_OUTPUT=$(snapraid status | grep -P "^(\s+[0-9]+\s+[0-9]+\s+[0-9]+\s+[0-9\-\.]+\s+[0-9]+\s+[0-9]+\s+[0-9\%]+.*)" \
                                | sed 's/ \+/ /g;s/^ //g;s/ - / 0 /g;s/[%-\.]//g')

NUM_LINES=$(wc -l <<<"$SNAPRAID_OUTPUT")

# We'll calculate the total wasted space in GB since snapraid status
# seems to output 0.0 no matter what.  We'll also make sure to convert
# GB to bytes for the output as per prometheus best practice.
wtt=0
i=1
echo "# HELP snapraid_files_total Number of files on snapraid device"
echo "# TYPE snapraid_files_total gauge"
while IFS= read -r line; do
    w=($line)
    echo "snapraid_files_total{device=\"${w[7]}\"} ${w[0]}"
done <<< "$SNAPRAID_OUTPUT"

# Since we dropped the decimal point the wasted bytes stat includes, remember to convert
# 100s of MB to B, *NOT* GB to B
echo "# HELP snapraid_wasted_bytes_total Number of bytes used for duplicate files"
echo "# TYPE snapraid_wasted_bytes_total gauge"
while IFS= read -r line; do
    w=($line)
    if [[ "$i" == "$NUM_LINES" ]]; then
        w[3]=$wtt
    else
        wtt=$((wtt+w[3]))
    fi
    echo "snapraid_wasted_bytes_total{device=\"${w[7]}\"} ${w[3]}"
    i=$((i+1))
done <<< "$SNAPRAID_OUTPUT"

# echo "$SNAPRAID_OUTPUT"
