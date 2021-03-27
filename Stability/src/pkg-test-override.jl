using Pkg

# Overrides the function that is called before the running of package tests
# History: the idea of this hack is taken from
# https://github.com/julbinb/juliette-wa/blob/9f6d4f24f31cb7e59b3928f1cc40c8380d8d3c40/src/analysis/dynamic-analysis/override-core/test-override.jl
function Pkg.Operations.gen_test_code(testfile::String;
        coverage=false,
        julia_args::Cmd=``,
        test_args::Cmd=``)
    code = """
        #### Prepare env (standard)
        #
        push!(LOAD_PATH, "@")
        push!(LOAD_PATH, "@v#.#")
        push!(LOAD_PATH, "@stdlib")
        $(Base.load_path_setup_code(false))
        cd($(repr(dirname(testfile))))
        append!(empty!(ARGS), $(repr(test_args.exec)))

        #### Prepare Stability.jl
        #
        stability_root = dirname("$(@__DIR__)")
        push!(LOAD_PATH, stability_root)
        using Stability
        pakg=ENV["STAB_PKG_NAME"]
        wdir=ENV["WORK_DIR"]
        #### End

        #### Run tests (standard + try-catch)
        #
        try
          @info "[Stability] [Package: " * pakg * "] Hooks are on. About to start testing"
          include($(repr(testfile)))
          @info "[Stability] [Package: " * pakg * "] Testing is finished successfully"
        catch error
          println("Warning: Error when running tests for package " * pakg)
        end

        #### Run Stability Analysis:
        #
        @info "[Stability] [Package: " * pakg * "] About to start analysis"
        m = eval(Symbol(pakg)) # typeof(m) is Module
        open(joinpath(wdir, "stability-errors.out"), "w") do err
          ms = module_stats(m, err)
          @info "[Stability] [Package: " * pakg * "] Computed module stats"
          s = modstats_summary(ms)
          @info "[Stability] [Package: " * pakg * "] Computed module summary. About to store results in a file"
          open(out -> println(out, pakg * "," * show_comma_sep(s)), joinpath(wdir, "stability-summary.out"), "w")
          st = modstats_table(ms)
          @info "[Stability] [Package: " * pakg * "] Table size: " * string(length(st))
          outf = joinpath(wdir, "stability-stats.txt")
          @info "[Stability] [Package: " * pakg * "] About to store results to: " * outf
          open(f-> println(f,st), outf,"w")
        end
        @info "[Stability] [Package: " * pakg * "] Finish testing + analysis"
        #### End
        """
    @debug code
    return ```
        $(Base.julia_cmd())
        --code-coverage=$(coverage ? "user" : "none")
        --color=$(Base.have_color === nothing ? "auto" : Base.have_color ? "yes" : "no")
        --compiled-modules=$(Bool(Base.JLOptions().use_compiled_modules) ? "yes" : "no")
        --check-bounds=yes
        --depwarn=$(Base.JLOptions().depwarn == 2 ? "error" : "yes")
        --inline=$(Bool(Base.JLOptions().can_inline) ? "yes" : "no")
        --startup-file=$(Base.JLOptions().startupfile == 1 ? "yes" : "no")
        --track-allocation=$(("none", "user", "all")[Base.JLOptions().malloc_log + 1])
        $(julia_args)
        --eval $(code)
    ```
end

