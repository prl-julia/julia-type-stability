#!/usr/bin/env bash
set -euo pipefail

cat $1 | sed s/,// | parallel ../../scripts/proc_package.sh
