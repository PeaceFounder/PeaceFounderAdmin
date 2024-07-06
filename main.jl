import PeaceFounderAdmin

function ReviseHandler(handle)
    req -> begin
        Revise.revise()
        invokelatest(handle, req)
    end
end

PeaceFounderAdmin.serve(server_middleware=[ReviseHandler], admin_middleware=[ReviseHandler], server_host="0.0.0.0")
