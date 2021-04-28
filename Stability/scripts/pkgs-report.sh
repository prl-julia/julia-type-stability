#!/usr/bin/env bash
set -euo pipefail
find . -maxdepth 2 -name stability-summary.out -exec cat {} + | sort | sed '1i package,methods,instances,stable,grounded,nospec,vararg,fail' > report.csv
