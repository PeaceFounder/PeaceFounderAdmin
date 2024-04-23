using Oxygen
using Mustache
using HTTP
using URIs

request(router::HTTP.Router, req::Request) = router(req)
request(url::URI, req::Request) = HTTP.request(req.method, URI(url; path = req.target), req.headers, req.body)

include("invite.jl")

TITLE::String = "Local Democratic Community"
PITCH::String = """
    <p> Are you looking for a way to get involved in local politics and make a difference in your community? Do you want to connect with like-minded individuals who share your values and beliefs? If so, we invite you to join our Local Democratic Community.</p>

<p> Our community is a group of individuals who are passionate about promoting progressive values and creating positive change in our neighborhoods and towns. We believe that by working together, we can build a more just and equitable society for everyone. As a member of our community, you will have the opportunity to attend events, participate in volunteer activities, and engage in meaningful discussions about the issues that matter most to you.</p>
"""

dynamicfiles(joinpath(@__DIR__, "static"), "/static")

INVITES::Dict{String, String} = Dict() # represents a local database

InviteCode.TOKEN_KEY = "a20c124aef6f5b75d6ea1f904c761e8d81ce05f6e6ce50f0f2a9568fc645f2f3" |> hex2bytes
InviteCode.TOKEN_LENGTH = 8

SERVER = URI("http://127.0.0.1:4584")


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


Oxygen.serve(port=3456)
