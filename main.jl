#include("src/PeaceFounderAdmin.jl")
#import HTTP

#import PeaceFounder
import PeaceFounderAdmin

# PORT = 4584

# try
#     #global service = HTTP.serve!(PeaceFounder.Service.ROUTER, "0.0.0.0", 4584)
#     service = PeaceFounder.Service.serve(async=true, port=PORT)

#     PeaceFounderAdmin.PEACEFOUNDER_SERVER_PORT = PORT
#     PeaceFounderAdmin.serve(port=3221)

# finally 
#     close(service)
# end


function ReviseHandler(handle)
    req -> begin
        Revise.revise()
        invokelatest(handle, req)
    end
end


PeaceFounderAdmin.serve(server_middleware=[ReviseHandler], admin_middleware=[ReviseHandler])
