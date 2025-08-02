import PeaceFounderAdmin

if !isempty(ARGS) && startswith(ARGS[1], "--load=")
    load_file = replace(ARGS[1], "--load=" => "", count=1)
    @info "Loading file: $load_file"
    @eval include(load_file)
end

if @isdefined(Revise)
    function ReviseHandler(handle)
        req -> begin
            Revise.revise()
            invokelatest(handle, req)
        end
    end
else
    function ReviseHandler(handle)
        return handle
    end
end


launch = () -> PeaceFounderAdmin.serve(server_middleware=[ReviseHandler], admin_middleware=[ReviseHandler], server_host="0.0.0.0")

if Base.isinteractive()
    @info "Starting service with interactive REPL"
    @async launch()
else
    launch()
end
