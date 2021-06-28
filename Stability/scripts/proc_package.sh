#!/usr/bin/env bash
set -euo pipefail

if [[ -z ${1+x} ]]; then
    echo "Error: Make sure to pass package name and version. Bye!"
    exit 1;
fi
args=( $1 )
pkg="${args[0]}"
ver="${args[1]}"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
mkdir -p "$pkg/depot"
pushd $pkg
STABILITY_HOME="$DIR/../"
DEV=YES JULIA_DEPOT_PATH="`pwd`/depot" STABILITY_HOME="$STABILITY_HOME" timeout 1800 julia -L "$STABILITY_HOME/startup.jl" -e "package_stats(\"$pkg\",\"$ver\")"
popd
