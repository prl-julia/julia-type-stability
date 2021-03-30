#!/usr/bin/env bash
set -euo pipefail
find . -name stability-summary.out -exec cat {} + | sort | sed '1i package,instances,stable,grounded,fail' > report.csv
