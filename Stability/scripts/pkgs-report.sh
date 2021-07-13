#!/usr/bin/env bash
set -euo pipefail
#find . -maxdepth 2 -name stability-summary.out -exec cat {} + | sort | sed '1i package,Methods,Instances,stable,grounded,nospec,vararg,Fail' > report.csv

function report {
    for p in $(awk '{print $1}' $1); do
        ofile="$p/stability-summary.out"
        if [ -f $ofile ]; then
            cat $ofile
        fi
    done
}

if [[ $# -eq 0 ]] ; then
    find . -maxdepth 2 -name stability-summary.out -exec cat {} + | sort | sed '1i package,Methods,Instances,stable,grounded,nospec,vararg,Fail' > report.csv
else
    res=$(report $1)
    lines=$(echo "$res" | wc -l | awk '{print $1}')
    res2=$(echo "$res" | head -n ${2:-$lines})
    echo "$res2" | sed '1i package,Methods,Instances,stable,grounded,nospec,vararg,Fail' > report.csv
fi
