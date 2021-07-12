#!/usr/bin/env bash
set -euo pipefail
find . -maxdepth 2 -name stability-summary.out -exec cat {} + | sort | sed '1i package,Methods,Instances,stable,grounded,nospec,vararg,Fail' > report.csv
