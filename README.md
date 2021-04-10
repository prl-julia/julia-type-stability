# Julia Type Stability Study

Some notes can be found on the
[wiki](https://github.com/ulysses4ever/julia-type-stability/wiki).

## Prereq's

``` sh
make deps
```

## Quick Start: REPL

Starting from `./Stability` do:

```sh
./startup.jl
```

Then, in Julia prompt:

``` julia
loop_pkgs_stats("top-10.txt")
```

to run stability analysis on top 10 Julia packages.
To compose the report, escape form Julia to Bash for a moment (`;`) and do:

``` sh
../scripts/pkgs-report.sh
```

this will create `report.csv` in `./Stability/pkgs`.

## CLI Interface

Some useful scripts live in `Stability/scripts`. E.g. to process a list of packages, you may use:

```
scripts/proc_packages_parallel.sh top-10.txt
```

If this works fine, you should be able to get a set of plots using

```
scripts/plot.sh top-10.txt
```

`

