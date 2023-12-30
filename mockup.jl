using Oxygen

staticfiles(joinpath(@__DIR__, "public"), "/")
staticfiles(joinpath(@__DIR__, "mockup"), "/")

Oxygen.serve(port=3221)
