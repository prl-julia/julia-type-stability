#!/usr/bin/env bash
set -euo pipefail
find . -name stability-summary.out -exec cat {} + | sed '1i package,instances,stable,generic,undef,fail' > report.csv
