#!/usr/bin/env bash
set -euo pipefail

if [[ -z $1 ]]; then
    echo "Make sure to pass package name"
    exit 1;
fi
p="$1"
mkdir -p "$p/depot"
pushd $p
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
STABILITY_HOME="$DIR/../"
DEV=YES JULIA_DEPOT_PATH="`pwd`/depot" STABILITY_HOME=$STABILITY_HOME julia -L "$STABILITY_HOME/startup.jl" -e "package_stats(\"$p\")"
popd
