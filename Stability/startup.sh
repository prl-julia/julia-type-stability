#! /usr/bin/env bash
# NOTE: Run from the Stability directory!
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
STABILITY_HOME="$DIR"
DEV=YES PAR=NO STABILITY_HOME=$STABILITY_HOME julia -p 32 -L ./startup.jl
