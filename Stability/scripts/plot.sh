#!/usr/bin/env bash
set -euo pipefail
if [[ -z ${1+x} ]]; then
    echo "Error: Make sure to pass filename with list of packages. Bye!"
    exit 1;
fi
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
julia -O0 -L "$DIR/plot.jl" -e "plot_all_pkgs(\"$1\")"
