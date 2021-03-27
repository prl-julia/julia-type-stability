#!/usr/bin/env bash
set -euo pipefail
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
julia -O0 -L "$DIR/plot.jl" -e "plot_all_pkgs(\"$1\")"
