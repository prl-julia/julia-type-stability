#!/usr/bin/env bash
set -euo pipefail
find . -maxdepth 2 -name stability-summary.out -exec cat {} + | sort | sed '1i package,instances,stable,grounded,fail' > report.csv
