#!/usr/bin/env bash
set -euo pipefail

cat $1 | parallel ../../scripts/proc_package.sh
