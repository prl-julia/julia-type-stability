#! /usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
STABILITY_HOME="$DIR"
DEV=YES PAR=NO STABILITY_HOME=$STABILITY_HOME julia -L "$DIR/startup.jl"
