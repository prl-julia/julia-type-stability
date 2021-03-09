#!/usr/bin/env bash
set -euo pipefail

julia -L ../scripts/plot.jl -e "plot_all_pkgs(\"top-10.txt\", :size)"
