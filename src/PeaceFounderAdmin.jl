module PeaceFounderAdmin

using Mustache
using Infiltrator
using PeaceFounder
using UUIDs

using PeaceFounder.Model: CryptoSpec, pseudonym, TicketID, Membership, Proposal, Ballot, Selection, generator, state, id, vote, seed, tally, approve, istallied, DemeSpec, hasher, HMAC, token, isbinding, Generator, generate, Signer

module AdminService using Oxygen; @oxidise end
import .AdminService: @get, @put, @post, @delete, Request, Response, dynamicfiles


module SETTINGS

SERVER_ROUTE::String = ""

SMTP_EMAIL::String = "" 
SMTP_PASSWORD::String = ""
SMTP_SERVER::String = "" # I did put a placeholder

#INVITE_DEME_ADDRESS = ""
INVITE_SUBJECT::String = "Membership Invite to Deme" # I could use {{DEME}}
INVITE_TEXT::String = """

Dear {{{NAME}}},

To begin your journey with PeaceFounder, simply launch the PeaceFounder client on your device and enter the invite code shown below. The rest of the process will be handled automatically by your device.

{{{INVITE}}}

Once registered, on your device you'll see a registration index, indicating your membership certificate's inclusion in BraidChain ledger. This index confirms your successful registration.

For auditing and legitimacy, please send a document within two weeks listing your registration index and the invite code, signed with your digital identity provider. Note that failure to complete this step will result in membership termination.

Guardian
{{DEME}}\

"""

# can be dynamically generated
# however may benefit for providing a granular handles
@eval function reset()

    global SERVER_ROUTE = $SERVER_ROUTE

    global SMTP_EMAIL = $SMTP_EMAIL
    global SMTP_PASSWORD = $SMTP_PASSWORD
    global SMTP_SERVER = $SMTP_SERVER

    global INVITE_SUBJECT = $INVITE_SUBJECT
    global INVITE_TEXT = $INVITE_TEXT
    
    return
end


hassmtp() = !isempty(SMTP_EMAIL) && !isempty(SMTP_SERVER) && !isempty(SMTP_PASSWORD)

end


SETUP_DONE::Bool = false # Consider puttin within settings


function serve(mock::Function = () -> nothing; server_port=4584, server_host="127.0.0.1", server_route=nothing, admin_port=3221, admin_middleware=[], server_middleware=[])

    # This is the stage where the server may read out user ssettings to read out files

    if isnothing(server_route)
        SETTINGS.SERVER_ROUTE = "http://$server_host:$server_port"
    else
        SETTINGS.SERVER_ROUTE = server_route
    end
        
    server_service = PeaceFounder.Service.serve(async=true, port=server_port, host=server_host, middleware=server_middleware)
    admin_service = AdminService.serve(port=admin_port, middleware=admin_middleware, async=true)
    
    try 
        
        mock()
        wait(admin_service)

    finally

        close(server_service)
        close(admin_service)
        SETTINGS.reset() 
        global SETUP_DONE = false

    end
end




const TEMPLATES = joinpath(dirname(@__DIR__), "templates")
dynamicfiles(joinpath(dirname(@__DIR__), "public"), "/") # Static files would also be fine here



function chunk_string(s::String, chunk_size::Int)
    return join([s[i:min(i+chunk_size-1, end)] for i in 1:chunk_size:length(s)], " ")
end

function render(fname, args...; kwargs...) # I could have a render template
    
    dir = pwd()
    
    try
        cd(dirname(fname))

        tmpl = Mustache.load(fname)
        return Mustache.render(tmpl, args...; kwargs...)
        
    finally
        cd(dir)
    end
end


function ordinal_suffix(day)
    if day in [11, 12, 13]
        return "th"
    elseif day % 10 == 1
        return "st"
    elseif day % 10 == 2
        return "nd"
    elseif day % 10 == 3
        return "rd"
    else
        return "th"
    end
end

# Function to format the date
function format_date_ordinal(date)
    # Extract components of the date
    year = Dates.year(date)
    month = Dates.format(date, "u")
    day = Dates.day(date)
    hour = Dates.hour(date)
    minute = Dates.minute(date)
    
    # Combine components with the ordinal suffix
    formatted_date = string(month, " ", day, ordinal_suffix(day), " ", year, " at ", lpad(hour, 2, '0'), ":", lpad(minute, 2, '0'))
    
    return formatted_date
end


############################ WIZARD ENDS #######################


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



include("setup.jl")
include("settings.jl")
include("registrar.jl")
include("braidchain.jl")
include("ballotbox.jl")
include("status.jl")


end
