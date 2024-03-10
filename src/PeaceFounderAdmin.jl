module PeaceFounderAdmin

using Mustache
using Infiltrator
using PeaceFounder
using UUIDs

using PeaceFounder.Model: CryptoSpec, pseudonym, TicketID, Membership, Proposal, Ballot, Selection, generator, state, id, vote, seed, tally, approve, istallied, DemeSpec, hasher, HMAC, token, isbinding, Generator, generate, Signer

module AdminService using Oxygen; @oxidise end
import .AdminService: @get, @put, @post, @delete, Request, Response, dynamicfiles


const TEMPLATES = joinpath(dirname(@__DIR__), "templates")
dynamicfiles(joinpath(dirname(@__DIR__), "static"), "/static") # Static files would also be fine here


include("utils.jl")
include("setup.jl")
include("settings.jl")
include("registrar.jl")
include("braidchain.jl")
include("ballotbox.jl")
include("status.jl")


# TODO: Add a setup middleware layer to isolate from the admin panel unless setup is done
@get "/" function(req::Request)

    #if !iscaptured()
    if !SETUP_DONE
        return Response(302, Dict("Location" => "/setup"))
    elseif !SETTINGS.hassmtp()
        return Response(302, Dict("Location" => "/settings"))
    else
        return Response(302, Dict("Location" => "/status"))
    end
end


# Isolates the setup phase from the dashboard
function SetupMiddleware(handler)
    return function(req::Request)
        if startswith(req.target, "/static")
            return handler(req)
        else
            if req.target in ["/setup", "/configurator", "/setup-summary"] 
                return SETUP_DONE ? Response(302, Dict("Location" => "/")) : handler(req)
            else
                return SETUP_DONE ? handler(req) : Response(302, Dict("Location" => "/setup"))
            end
        end
    end
end


function serve(mock::Function = () -> nothing; server_port=4584, server_host="127.0.0.1", server_route=nothing, admin_port=3221, admin_middleware=[], server_middleware=[])

    # This is the stage where the server may read out user ssettings to read out files

    if isnothing(server_route)
        SETTINGS.SERVER_ROUTE = "http://$server_host:$server_port"
    else
        SETTINGS.SERVER_ROUTE = server_route
    end

    server_service = PeaceFounder.Service.serve(async=true, port=server_port, host=server_host, middleware=server_middleware)
    admin_service = AdminService.serve(port=admin_port, middleware=[admin_middleware..., SetupMiddleware], async=true)
    
    try 
        
        mock()
        wait(admin_service)

    finally

        close(server_service)
        close(admin_service)
        SETTINGS.reset() 
        global SETUP_DONE = false
        global ELECTORAL_ROLL = ElectoralRoll()
    end
end


end
