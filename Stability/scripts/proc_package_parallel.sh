#!/usr/bin/env bash

# Batch processing of packages for type stability analysis.
# Arguments:
#   $1 -- file with a list of packages; every line there is of "name version" format;
#   $2 -- optional, number of first lines in $1 to consider.
# Output:
#   In the current dir creates a set of subdirs named after packages listed in $1;
#   with the type stability analysis results; also creates a summary report in the
#   current directory (report.csv).
# Notes
#   - piggy-backs on the proc_package.sh script to process each package;
#   - depends on GNU parallel at the moment; in theory, could instead just do
#     a sequential loop (TODO add this guarded by a parameter).

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

lines=$(wc -l $1 | awk '{print $1}')
head -n ${2:-$lines} $1 | parallel "$DIR/proc_package.sh"
$DIR/pkgs-report.sh $1 ${2:-$lines}
