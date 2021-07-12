#!/usr/bin/env bash
# Run from the root (ls shows Stability and shell.nix)

set -euo pipefail

wd=/home/artem/stability/scratch
out=$wd/artifact
rm -rf $out
mkdir -p $out

cp shell.nix $out/
cp Stability/pkgs/top-1000-ver.txt $out/top-1000-pkgs.txt
cp Overview.md $out/README.md

mkdir -p $out/Stability
cp -r Stability/scripts $out/Stability/
cp -r Stability/src $out/Stability/
cp Stability/startup.* $out/Stability/
cp Stability/Manifest.toml Stability/Project.toml $out/Stability/

mkdir $out/start
cp -r Stability/pkgs/fresh7/Multisets $out/start/
rm -f $out/start/Multisets/*.csv $out/start/Multisets/*.txt $out/start/Multisets/*.out
mv $out/start/Multisets/figs $out/start/Multisets/figs-ref

pushd $out > /dev/null
tar -czf ../artifact.tar.gz *
popd > /dev/null

