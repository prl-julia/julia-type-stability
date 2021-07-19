#!/usr/bin/env bash

#
# Generate summary report (report.csv)
#
# Call:
#
#   pkgs-repo.sh <package list> <# of first packages in the packakge list>
#
# both parameters are optional. If none is given, search for analysis summaries
# in all subdirs of the current dir.
#
# Assumes:
#   Stabilty analysis (using proc_package.sh) has finished in the current directory
#   producing raw data including summaries (stability-summaty.out files) in
#   subdirs of the current dir.
#

set -euo pipefail

SUMMARY_FILE="stability-summary.out"

function report {
    for p in $(awk '{print $1}' $1); do
        ofile="$p/$SUMMARY_FILE"
        if [ -f $ofile ]; then
            cat $ofile
        fi
    done
}

ADD_HEAD='1i package,Methods,Instances,stable,grounded,nospec,vararg,Fail'

if [[ $# -eq 0 ]] ; then
    find . -maxdepth 2 -name "$SUMMARY_FILE" -exec cat {} + | sort | sed "$ADD_HEAD" > report.csv
else
    res=$(report $1)
    lines=$(echo "$res" | wc -l | awk '{print $1}')
    res2=$(echo "$res" | head -n ${2:-$lines})
    echo "$res2" | sed "$ADD_HEAD" > report.csv
fi
