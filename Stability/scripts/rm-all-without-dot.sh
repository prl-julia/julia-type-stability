#!/usr/bin/env bash
set -euo pipefail

ls -1 | sed '/\./d' | xargs rm -rf
