using Oxygen

dynamicfiles(joinpath(dirname(@__DIR__), "public"), "/")
dynamicfiles(joinpath(dirname(@__DIR__), "mockup"), "/")

Oxygen.serve(port=3221)
