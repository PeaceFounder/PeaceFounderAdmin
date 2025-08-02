# This demo illustrates the ease of integration, as this registration form operates completely independently with HTTP requests secured via HMAC authorization using a shared secret and simple token derivation: token = SHA256(key|attempt|ticketid), where the ticketid is registered by the endpoint.

using Oxygen
using Mustache
using HTTP
using URIs

request(router::HTTP.Router, req::Request) = router(req)
request(url::URI, req::Request) = HTTP.request(req.method, URI(url; path = req.target), req.headers, req.body)

include("invite.jl")

TITLE::String = "Demo: PeaceFounder E-Voting System"
PITCH::String = """
  <p>Welcome to this PeaceFounder demonstration! This demo instance features simplified registration to showcase how any organization, community group, or workplace (deme) can deploy end-to-end verifiable remote voting using PeaceFounder.</p>

<p>This demonstration illustrates a complete e-voting system where members of any deme can participate in democratic decision-making. Administrators manage the deme through the PeaceFounder admin panel at http://127.0.0.1:3221, where they can add and revoke memberships, braid members, and issue proposals for voting. Note that only proposals submitted after your registration will be available for voting - this design enables anonymization before the voting phase begins, eliminating complex tallying ceremonies at the end.</p>
"""

dynamicfiles(joinpath(@__DIR__, "static"), "/static")

INVITES::Dict{String, String} = Dict() # represents a local database

if haskey(ENV, "REGISTRAR_TOKEN")
    @info "Using environemnt registrar token key"
    token_hex = ENV["REGISTRAR_TOKEN"]
elseif  isfile("/run/secrets/registrar_token") # consider adding && isfile("/run/.containerenv")
    @info "Loading registrar token from /run/secrets/registrar_token"
    token_hex = read("/run/secrets/registrar_token", String) |> strip 
end

# TODO: I have an issue with:
# Why did I adde another hash and simply did not use hmac?
# function token_key(hmac::HMAC) 
#     hash = hasher(hmac)
#     return hash(UInt8[0, key(hmac)...])
# end    

InviteCode.TOKEN_KEY = token_hex |> hex2bytes # The issue is with 
InviteCode.TOKEN_LENGTH = 8

SERVER = URI(get(ENV, "PEACEFOUNDER_SERVICE", "http://0.0.0.0:4584"))

@get "/" function(req::Request)
    template = Mustache.load(joinpath(@__DIR__, "assets", "index.html"))
    return template(; TITLE, PITCH) |> html
end

@post "/tickets" function(req::Request)
    (; name, email) = json(req)
    
    ticketid = rand(UInt8, 16)
    
    invite = InviteCode.create_profile(SERVER, name, email, ticketid)

    tid = bytes2hex(ticketid)

    INVITES[tid] = invite

    return Response(302, Dict("Location" => "/tickets/$tid"))
end


@get "/tickets/{tid}" function(req::Request, tid::String)
    
    if !haskey(INVITES, tid)
        return Response(404)
    end

    resp = request(SERVER, Request("GET", "/tickets/$tid"))

    _json = json(resp)
        
    template = Mustache.load(joinpath(@__DIR__, "assets", "invite.html"))

    if haskey(_json, :admission)
        BODY = """
        <h2>SUCCESS</h2>
        <p>Welcome to the deme! Your device now displays a registration index, confirming your membership in the BraidChain ledger. You are now eligible to vote on upcoming proposals with an anchor index larger than your registration index.</p>

        <p>
        For auditing purposes, please submit a signed document containing your registration index and invite code within two weeks to consent to your membership with the deme and prevent its termination after the trial period. Full instructions are sent to your email.
        </p>
        <div class="form-row-last" >
	  <a href="/" class="register">Return</a>
	</div>
    """
    else
        invite = INVITES[tid]
        (; timestamp) = _json

        BODY = """
        <h2>INVITE</h2>
        <p>To register to the deme enter a following invite code in PeaceFounder client:</p>
        <p class="code">$invite</p>
        <p>Upon successful registration, your device will display a registration index, confirming your membership in the BraidChain ledger, granting you the right to vote on upcoming proposals.</p>
        <div class="form-row-last" >
        <a class="register" onclick="location.reload();">Check</a>
	</div>

        """
    end

    return template(; TITLE, PITCH, BODY) |> html
end


Oxygen.serve(host="0.0.0.0", port=3456)
