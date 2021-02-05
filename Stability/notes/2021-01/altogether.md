# 2021-01-02

## No tests for Stability anymore (Issue #3)

As a result of interjecting (a part of) functionality of `Pkg.test` 
(in `src/pkg-test-override.jl`), I can't run tests for the `Stability` package 
itself, which is sad. I thought I could give away
with a sort of conditional inclusion of the relevant code, but for an unknown reason
the mere presence of the code in the package seems to interfere with `Pkg.test`.
So, I guess, I have to temporarily put testing on hold?

## Can't Process Generic Instances (Issue #2)

The problematic method instance from JSON uses a parametric struct with no fields.
Maybe that's the reason it has not been specialized. But it's hard to see how one
could repro this problem. E.g.:

    julia> struct S{T} end

    julia> s=S{Int64}()
    S{Int64}()

    julia> h(s::S{T}) where T = 3
    h (generic function with 1 method)

    julia> h(s)
    3

    julia> methodinstances(h)
    1-element Array{Core.MethodInstance,1}:
     MethodInstance for h(::S{Int64})

To summarize, creating an instance of such a structure (`s` of type `S` in the example)
requires to provide a type argument. And you see the same argument in the method instance
after you call a function with the instance.

## Finally, First Numbers

I finally was able to process a whole package -- JSON was my example.
Here're the numbers:

    FunctionStats(667, 509, 8, 6, 144)

The numbers mean (in order):

  occurs  :: Int  # how many occurances of the method found (all instances)
  stable  :: Int  # how many stable instances
  generic :: Int  # how many generic instances (we don't know how to handle them yet)
  undef   :: Int  # how many methods could not get resolved (for unknown reason)
  unstable:: Int  # how many unstable instances (just so that all-but-occurs sums up to occurs)

So, after executing JSON test suite I saw 667 compiled method instances, of which 509 are
stable, (8 + 6) I could not process because I can't process generic instances or
sometimes a method name could not be resolved for some reason.

You'll notice that we have two bins "can't process" now: `generic` and `undef`.
They are not too large (at least for JSON), so maybe I keep them for now?
For `generic` I don't know how to even reproduce the problem.
Same for `undef` but that one I did not try too hard to investigate.


# 2021-01-04

## Setting up pipeline

I need two bits to get to some more data:

1. Store results of the analysis in a file (instead of printing them). 
   (Issue #4)

2. A loop through packages (assuming I have a list of packages -- that 
   I can borrow from the WA project). (Issue #5)

# 2021-01-05

## Pipeline contd.


# 2021-01-08

## Recover from failures during analysis

# 2021-01-09

## First results on top-10 packages

|package              |instances|stable|generic|undef|fail|
|---------------------|---------|------|-------|-----|----|
|IJulia               |142      |93    |0      |0    |0   |
|Gen                  |1970     |1074  |24     |165  |2   |
|Knet                 |12596    |3141  |1387   |68   |206 |
|DifferentialEquations|8235     |4139  |199    |185  |42  |
|Gadfly               |43516    |31812 |245    |10   |80  |
|JuMP                 |32487    |18033 |893    |3069 |1368|
|Pluto                |88735    |59821 |1511   |74   |881 |
|Flux                 |4525     |3474  |107    |4    |0   |
|Plots                |5812     |3542  |82     |151  |10  |
|Genie                |2019     |1659  |18     |4    |15  |

(We got this with v0.1 of the pipeline, i.e. 0e3bb5cd).

