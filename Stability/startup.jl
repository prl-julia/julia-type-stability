using Pkg
Pkg.add("Revise")
using Revise
Pkg.activate(ENV["STABILITY_HOME"])
Pkg.instantiate()
using Stability
