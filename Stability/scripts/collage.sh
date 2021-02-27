#!/usr/bin/env bash
if [[ -z $1 && -z $2 ]]; then
    echo "Make sure to pass the column name (e.g. size) and grid size (e.g 4x2)"
    exit 1;
fi
col="$1"  # e.g. size
grid="$2" # e.g. 4x2
montage "by-$col/*.png" -geometry 1200x800+0+0 -tile "$grid" "all-by-$col.png"
