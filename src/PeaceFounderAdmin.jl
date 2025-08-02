module PeaceFounderAdmin

using Mustache
using PeaceFounder
using UUIDs

using PeaceFounder.Server: Mapper
using PeaceFounder.Core: Model
using PeaceFounder.Core.Model: CryptoSpec, Pseudonym, pseudonym, TicketID, Membership, Termination, Proposal, Ballot, Selection, generator, state, id, seed, tally, approve, istallied, DemeSpec, hasher, isbinding, Generator, generate, Signer

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
include("gitsync.jl")

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


const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    #"Access-Control-Allow-Headers" => "*, Authorization",
    "Access-Control-Allow-Headers" => "*, Authorization, Origin, X-Requested-With, Content-Type, Accept",
    "Access-Control-Allow-Methods" => "POST, GET, PUT, OPTIONS",
    "Access-Control-Expose-Headers" => "*"
]


function CorsMiddleware(handler)
    return function(req::Request)
        # determine if this is a pre-flight request from the browser
        if req.method == "OPTIONS"
            return Response(200, CORS_HEADERS)  
        else 
            response = handler(req) # passes the request to the AuthMiddleware
            append!(response.headers, CORS_HEADERS)
            return response
        end
    end
end


function serve(mock::Function = () -> nothing; server_port=4584, server_host="127.0.0.1", server_route=nothing, admin_host=get(ENV, "PEACEFOUNDER_ADMIN_HOST", "127.0.0.1"), admin_port=3221, admin_middleware=[], server_middleware=[])

    if admin_host!=="127.0.0.1"
        @warn "The admin host should only be accessed through secure, encrypted channels like an SSH tunnel or VPN. Your current server configuration leaves it exposed to potential sabotage. Ignore if used for demonstrative purposes or used through podman." 
    end
    # This is the stage where the server may read out user ssettings to read out files

    if haskey(ENV, "USER_DATA") && !isempty(ENV["USER_DATA"])

        Mapper.DATA_DIR = ENV["USER_DATA"]
        SETTINGS.PATH = joinpath(ENV["USER_DATA"], "Settings.toml")
        global REGISTRAR_PATH = joinpath(ENV["USER_DATA"], "private", "registrar")
                
        @info """User data set to $(ENV["USER_DATA"])"""

        if isempty(filter(!=("config"), readdir(ENV["USER_DATA"])))
            @info "Starting fresh with setup"
        else
            try 
                Mapper.load_system()
                global SETUP_DONE = true
                @info "System is succesfully reinitialized from previous state"
            catch err
                @error "Initialization from previous state has failed. Use `Mapper.load_system()` to investigate."
                throw(err)
            end

            global ELECTORAL_ROLL = load(ElectoralRoll, joinpath(REGISTRAR_PATH, "records"))

            try
                SETTINGS.load()
                @info "Settings are loaded"
            catch err
                @warn "Could not load previous settings. Preceeding with defaults."
                throw(err)
            end
        end
    else
        Mapper.DATA_DIR = ""
        SETTINGS.PATH = ""
    end

    # SETTINGS.PATH

    if !isnothing(server_route)
        SETTINGS.SERVER_ROUTE = server_route
    elseif isempty(SETTINGS.SERVER_ROUTE)
        SETTINGS.SERVER_ROUTE = "http://$server_host:$server_port"
    end

    if SETUP_DONE
        Mapper.set_route(SETTINGS.SERVER_ROUTE)    
    end

    server_service = PeaceFounder.Server.Service.serve(async=true, port=server_port, host=server_host, middleware=[server_middleware..., CorsMiddleware])
    admin_service = AdminService.serve(port=admin_port, host=admin_host, middleware=[admin_middleware..., SetupMiddleware], async=true)
    
    try 
        
        mock()
        SETTINGS.store()
        wait(admin_service)

    finally

        close(server_service)
        close(admin_service)
        #SETTINGS.reset() 
        global SETUP_DONE = false
        global ELECTORAL_ROLL = ElectoralRoll()
    end
end


end
