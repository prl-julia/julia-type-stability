#!/usr/bin/env bash
set -euo pipefail

#
# Process/validate arguments:
# - args[0] -- package name
# - args[1] (optional) -- package version
#
if [[ $# -eq 0 ]]; then
    echo "Error: missing arguments. Provide package name to process and, optionally, its version."
    exit 1
fi
args=( $1 )
pkg="${args[0]}"
if (( ${#args[@]} == 2 )); then
    ver="${args[1]}"
    PACKAGE_STATS_CALL="package_stats(\"$pkg\",\"$ver\")"
elif ! [ -z ${2+x} ]; then
    ver="$2"
    PACKAGE_STATS_CALL="package_stats(\"$pkg\",\"$ver\")"
else
    PACKAGE_STATS_CALL="package_stats(\"$pkg\")"
fi

# Record current directory. Note: don't move around or it'll stop working!
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Silent versions of pushd/popd
pushd () {
    command pushd "$@" > /dev/null
}
popd () {
    command popd "$@" > /dev/null
}

#
# Prepare and cd into clean directory
# Intend to keep Julia depot there, so make a dir for it
#
mkdir -p "$pkg/depot"
pushd $pkg

#
# Call Julia with a timeout
#
STABILITY_HOME="$DIR/../"
DEV=YES JULIA_DEPOT_PATH="`pwd`/depot" STABILITY_HOME="$STABILITY_HOME" timeout 2400 julia -L "$STABILITY_HOME/startup.jl" -e "$PACKAGE_STATS_CALL"
popd

# ATTENTION
# The rm below is needed when run over big set of packages so that we don't run out
# of disk space. Otherwise it's pretty expensive to restart the analysis.
# rm -rf "$pkg/depot"
