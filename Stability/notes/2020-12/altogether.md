# 2020-12-05

## Coding

Studying the implementation of (Julia's standard) `code_warntype` 
([[doc]](https://docs.julialang.org/en/v1/manual/performance-tips/#man-code-warntype)
for the macro, 
[[code]](https://github.com/JuliaLang/julia/blob/788b2c77c10c2160f4794a4d4b6b81a95a90940c/stdlib/InteractiveUtils/src/codeview.jl#L34) for the function), 
which prints information about type stability. 
This should help figuring out how to get this information programmatically. 
I'd need to write a utility that given function name and types of arguments 
returns `true` / `false` (whether the code is stable) instead of printing. 
Let's call this utility `is_stable_call`.

The [current version of `is_stable_call`](https://github.com/ulysses4ever/julia-type-stability/blob/545485142771601787f4664fcaef02241982e964/check_stability.jl#L23) 
doesn't work: see the comment with TODO in the code.



## Maybe useful tools
ulysses4ever-patch-1
[`Cassette.jl` package](https://github.com/jrevels/Cassette.jl) -- could be useful 
to analyze Julia code being executed without intervention into the VM. 
Hopefully, I could hook up is_stable so that it is called for every function call. 
Running a test suite of a package should then give me a number of (un)stable calls.

## Useful sources

Looking through mentions of type stability on the Internet, I found a [nice blog post](http://www.johnmyleswhite.com/notebook/2013/12/06/writing-type-stable-code-in-julia/) going back to 2013, which introduces this notion. One curious thing about it: they showed an experiment where the difference in run-time between type stable code and its unstable analog was 50x. 

I tried their experiment on today's Julia (1.5.2) and it was "only" 5x. Even more exciting, on Julia 1.5.3 the difference is 5%. **UPD** I can't reproduce the 5x figure anymore, it seems. Now it's more like 25% of slowdown for me.

# 2020-12-07

## Coding

### TODO from last time
TODO from [[2020-12-05]] (error when calling `is_stable_call`) is solved: the error was due to a typo (instead of the `is_stable_type` helper function we called `is_stable_call` recursively).

### Created a package

Now `is_stable_call` seems to work. I packaged it (see the 
[`Stability`](https://github.com/ulysses4ever/julia-type-stability/blob/c76fd5a2313120b674045833f7a59dfd4a398f7e/Stability)
directory and
[`Stability/src/Stability.jl`](https://github.com/ulysses4ever/julia-type-stability/blob/c76fd5a2313120b674045833f7a59dfd4a398f7e/Stability/src/Stability.jl)
in particular), added a couple of
[tests](https://github.com/ulysses4ever/julia-type-stability/blob/c76fd5a2313120b674045833f7a59dfd4a398f7e/Stability/test/runtests.jl)
(run `make test` inside the `Stability` dir).

## Plannnig

To perform the study, we need to learn how to intercept method calls to log the call's stability. There are (at least) two options:

* Hack into VM

* use Cassette.jl

Jan thinks Cassette may be a trap: work for starters, but fail when something non-trivial is needed, 3 months down the road, which may be really bad. 

If we hook up into the VM, an interesting question: when to record stability, at every call or at every compilation.

### Performance

In light of interesting time stats (cf. end pf [[2020-12-05]])... it's hard to make a general performance argument. Better to start with measuring the amount of instability, talk about performance foot print in isolated cases.

## Action items:

* Talk to Ben about Cassette.

* Look into Cassette.

* Ping Jan when some data is in.


## Further developments

Ben suggest avoiding Cassette.jl as not robust enough (failing on some packages in his experience). Instead he advices to analyze the set of compiled methods using, e.g. [MethodAnalysis.jl](https://github.com/timholy/MethodAnalysis.jl).

# 2020-12-11

# MethodAnalysis.jl experimenting

The package provides access to all compiler-so-far methods,
which is less than all methods but still is an interesting subset:
imagine we start querring it after running some package's test
suite.

The main representation of a compiled method in this package
is the `Core.MethodInstance` type (so, Julia's standard type).
It seems to have a lot of data in it. I don't understand most of it at this point. Notably, for one simple method with a loop in it, the MethodInstance object has a 1000+-element array of `specializations.

Note that many relevant datatypes (e.g. `MethodInstance` mentioned
above, `CodeInfo` that `code_typed` returns and we compute 
`is_stable_call` with) are documented on the 
[devdocs section]()
of Julia manual.

**Problem**
`MethodInstance` has method name and signature, but I don't see 
where to get the particular types of arguments it was compiled for. 
[Julia's manual](https://docs.julialang.org/en/v1/devdocs/ast/#Lowered-form) (devdocs about `Slots`) mentions that 
a `MethodInstance` should have `slottypes` -- 
that's exactly what we use in `is_stable_call` --
unfortunately, it seems the doc is wrong: I get

> ERROR: type MethodInstance has no field slottypes

[The source of the type](https://github.com/JuliaLang/julia/blob/2e3364e02f1dc3777926590c5484e7342bc0285d/src/jltypes.c#L2216)
 (which is builtin and. therefore, is a 
part of the `Core` module) agrees that there's no such field.

**Solution**
The `specTypes` field in `MethodInstance` seems to be the right 
field.

Also, I have filed 
[a documentation issue](https://github.com/JuliaLang/julia/issues/38840) 
to the Julia bug tracker. Tim Holy argeed and suggested changing 
`MethodInstance` with `CodeInfo`, which I did (see [PR 38843](https://github.com/JuliaLang/julia/pull/38843)).

**Problem**
Types of arguments are not enough: we need type of all slots.

**Possible Solution**
We could grab the method name and `specTypes` and
call `is_stable_call`.

**Problem**
`code_typed` (and `code_warntype` which depends upon it)
runs type inference on the AST and processes `CodeInfo` that 
TI returns. Whereas `MethodInstance` has, at best, `CodeInstance`.
How to make them friends is stil unclear.
(compiled) IR stuff.

# 2020-12-12

## Connecting `MethodInstance` and `is_stable_call`: `is_stable_instance`

A `MethodInstance` object (e.g. `mi`) seem to have everything 
that we need for
`is_stable_call`: method name (via `mi.def.name`) and types
of specific arguments for which this `mi` has been compiled
(`mi.specTypes`). 

As a sidenote, we don't seem to be able to extract 
stability directly from `mi` (bypassing `is_stable_call`): 
stability is concerned with 
type inference process that preceeds compilation (and on which 
compilation is based), but after compilation is done and an `mi`
is produced this information seem to not preserve anymore.

Specifically, the method name we can get by `eval(mi.def.name)`.
The argument types, I can't still figure out what to do with --
**problem**.

`mi.specTypes` is a tuple **type** (e.g. `Tuple{typeof(foo),Array{Int64,1}}` for a `mi` representing code
of `foo` called with an array). 
I need the object corresponding to this type (e.g.
`(Array{Int64,1},)` -- a 1-element tuple object holding a type 
in its first component).

**Solution**
`mi.specTypes.types[2:end]` seem to be legit argument for `is_stable_call` pipeline (docs on `DataType`'s, of which
`mi.specTypes` is an instance of, helped)

Sidenote: tried to form a small package aruond `is_stable_call`
and `is_stable_instance` -- Julia's packaging is (as always) a mess.

Useful: `MethodAnalysis` has the `methodinstances` function to
get all MIs of a given function (e.g. `methodinstances(sumofsins1)`).

**Finally**
Added `is_stable_instance` and `all_mis_of_module`.
They seem to work well together, although I should add minimal
tests!

# 2020-12-15

## Pkg is painful

I probably need to be `using Revise` before loading my package `Stability`
to have the source of Stability updated without reloading anything manually.
So the correct sequence of actions on startup is:

```
julia> using Revise
pkg>activate path/to/Stability
julia> using Stability
```

This assumes Revise is in the global environment (thanks Ben!). If not, add
`pkg>add Revise` as the first command.

# Modules are painful

I want to test MethodInstance-based utilities (`all_mis_of_module` and
`is_stable_instance`) in the test suite of the package. This requires to
defined some `Foo`/`Bar`-modules. When I try to be `using` (or `import`)
those modules, Julia gives me an error about _package_ `Foo` -- which I don't
have, of course!

**Solution**
I should be `using Main.Foo`...

# 2020-12-18

## Planning a mock of analysis

Today I want to construct a test running just like I wish the future analysis
will run. So, I have a target module at the input, and the invariant that some
of its "interesting" functions have alredy been compiled (basically, called).
As the output I want some sort of report about which functions were there
and weather they hold type stability.

As a first step, I want to add a test for `all_mis_of_module` -- done in fcacb37.

Next up, a function to compute stats for the given module. But, we need a stats
data structure first. What should we include there? Is it as simple as a vector
of data about functions? From the practical point of view, maybe it's handier
to have a map: function-name -> (#all instances, number of stable instances).

I finished with the design. Implement tomorrow.

# 2020-12-19

Today we implemented yesterday's plan and now have:

* `ModuleStats` structure holding the module name and a dictionary from function names to `FunctionStats` structure.

* `FunctionStats` (mutable) structure with two fields: `occurs` — the number of method instances found compiled, and `stable` — the number of stable instances (`stable ≤ occurs`).

* `module_stats` function that given a module name generate a `MethodStats` for it. Important to remember that for the result to be non-empty we need to run functions from the module before calling the `module_stats` function.

We have a test showing how to load a module, call its functions, and run `module_stats` to get the stats.

The next task is to figure out how to automate this test scenario. We probably need to enumerate packages (maybe start with a list of packages read from a file), and for every package (maybe in parallel?)  **in a clean environment** (?)`Pkg.add` it, then `Pkj.test` it, and finally call `module_stats` with the same-as-package-named module.

# 2020-12-21

## Up to the package level

Previously, we gradually moved from testing a type for stability to testing 
a function call, then a method instance, and finally, a module. Now, we move 
one more level up -- at the package level.

We want to have a somewhat clean environment to import and test any given package.
Julia's `Pkg` facility seems to allow for that. 

Hint: when drafting the logic to implement the above, I find it
useful to be able to import the `Stability` package into a clean local environment.
This can be done with

    Pkg.add(path="path/to/repo", subdir="Stability")

(This is less straightforward than one would want because the package is located 
in a subdirectory of the repo, and Julia's `Pkg` by default assumes the package
and the repo are at the same level… yes, it does require you to have a git repo.)

A **small issue**
I'm having here is how to get from a package name (of type `String`) to the
corresponding module name (of type `Module`). The simplest construction that
does not error is `Module(Symbol(pkg_name))` but it gove back the module prefixed
with `Main` (e.g. for `"JSON"` it will give `Main.JSON`) which does not make sense.

A heavy artillery **solution**
for this seems to be:

    eval(Meta.parse("using $(pakg)"))
    m = eval(Symbol(pakg)) # typeof(m) is Module

### Testing JSON package

The above strategy is implemented, and I'm trying it out against the JSON package.
It is not successful so far: the return `ModuleStats` has only one 
method instance in it -- `include` -- called thrice.
I assume, the ** problem** is that `Pkg.test` forks a separate Julia process.

# 2020-12-22

## How To Test

I need to learn how to run a package test suite in the current process — so that 
I have all method instances left in my current VM session.

Turns out (thanks Yulia!) the world-age project has a solution for a similar
task (they needed to redefine `eval` for the time of `Pkg.test`) here:

> https://github.com/julbinb/juliette-wa/blob/master/src/analysis/dynamic-analysis/override-core/test-override.jl

Although the task is different, it may be best to follow their idea and not escape 
the `Pkg.test` sandbox (as I envisioned before: I wanted just `include`
the `runtests.jl`). But then I need to be able to load `Stability` into the sandbox -- **problem**.
E.g. they do `Pkg.add` to get their dependencies in scope. I think it's a bit over pessimistic:
this initiates Pkg's resolver, which is sloppy, every time. It'd be cool to add a path to
`Stability` right away, so that we can just be `using` it.

**Solution** seems to be adding `Stability` to `LOAD_PATH` during creation of
the sandbox.

Another **problem**
is how to right back the results of analysis. I assume, two things are needed:

1) a storable format for results (probably, JSON); 

2) an environment variable `OUPTUT_DIR`. Also, another env variable is probably 
    useful: the name of the package being tested.

# 2020-12-26

## Hacking into Pkg.test

After reading about World-Age project's approach to overriding `Pkg.test`,
I figured:

* I'm not sure I need sandboxing for package analysis, because `Pkg.test` creates a
  sandbox;

* I need to set environment vriables to send data in the hook inside `Pkg.test`;

* I need to learn how to store `ModuleStats`/`FunctionStats` as JSON.

Regarding the first point: as long as `Pkg.test` don't install (`Pkg.add`),
I probably do need my own sandbox too, after all.

### First prototype

is done as of [9f52b2d](https://github.com/ulysses4ever/julia-type-stability/commit/9f52b2d0666af2dfb5e7f630341a9e1dfb9fca2f). It errors on the JSON package for some reason:

```
ERROR: type UnionAll has no field types
Stacktrace:
 [1] getproperty(::Type{T} where T, ::Symbol) at ...julia-1.5.3/lib/julia/sys.so:?
 [2] is_stable_instance(::Core.MethodInstance) at /home/artem/research/julia-type-stability/repo/Stability/src/Stability.jl:73
 [3] module_stats(::Module) at /home/artem/research/julia-type-stability/repo/Stability/src/Stability.jl:111
```

#### Useful links

WA project's `Pkg.test` hacking:

* [entry point](https://github.com/julbinb/juliette-wa/blob/master/src/analysis/dynamic-analysis/analyze-package.jl)

* [hook](https://github.com/julbinb/juliette-wa/blob/master/src/analysis/dynamic-analysis/override-core/test-override.jl)

# 2020-12-28

## Generic types in method instances

When running analysis on the JSON package I got an exception for the method
instance of the following type:

    Tuple{
      typeof(JSON.Parser.int_from_bytes),
      JSON.Parser.ParserContext{DictType,IntType,AllowNanInf,NullValue} 
        where NullValue 
        where AllowNanInf 
        where DictType,
      JSON.Parser.StreamingParserState{IOStream},
      Array{UInt8,1},
      Int64,
      Int64} where IntType<:Real

(So, this is a compiled method of the `int_from_bytes` function.) 
The problem is the outer `where`. My pipeline currently does not know what to do
with it: we expect a plain `Tuple`. 

Interestingly, type stability (as identified by `@code_warntype`)
seems to not depend on how abstract type arguments of parametric types are. E.g.

    julia> f(a :: Vector{Any}) = 1
    f (generic function with 1 method)

    julia> a = ['1', 3.4]
    2-element Array{Any,1}:
      '1': ASCII/Unicode U+0031 (category Nd: Number, decimal digit)
     3.4

    julia> @code_warntype f(a)
    [No warnings]

So a function accepting something like `Vector{T} where T <: Any` (or, simply,
`Vector{Any}`) can be type-stable.

I'm not sure what to do with such types. I could try to manually unwrap `where`s
but this feels a bit hacky. I probably stick to this idea and see how it goes.

### Issue with `package_stats`

Unrelated and mnor technical [issue #1](https://github.com/ulysses4ever/julia-type-stability/issues/1): I need to do proper restoration of the current directory.

