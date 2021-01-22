# Julia Type Stability Study

Some notes can be found on the
[wiki](https://github.com/ulysses4ever/julia-type-stability/wiki).

## Prereq's

``` sh
make deps
```

## Quick Start

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
