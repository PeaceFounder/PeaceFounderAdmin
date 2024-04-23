using Nettle
using HTTP: HTTP, Request, Response
using Base64
using PeaceFounder.Authorization: AuthClientMiddleware # In future this will be in a seperate package
using PeaceFounder.Base32: decode_crockford_base32 # In future this will be in a seperate package
using URIs
using Base: UUID
using JSON3

request(server::URI, req::Request)::Response = HTTP.request(req.method, URI(server; path = req.target), req.headers, req.body)

sha256(data) = Nettle.digest("sha256", data)

function credential(code::Vector{UInt8})
    _hash = sha256(code)
    return Base64.base64encode(_hash)
end


function track_vote(server::URI, proposal::UUID, code::Vector{UInt8})
    
    req = Request("GET", "/poolingstation/$proposal/track", ["Host" => string(server)])    
    
    _credential = credential(code)
    response = req |> AuthClientMiddleware(req -> request(server, req), _credential, code)

    if response.status == 200
        return JSON3.read(response.body)
    else
        error("Request failure $(response.status): $(String(response.body))")
    end
end

function track_vote(server::URI, proposal::UUID, code::String)
    code_bytes = replace(code, "-" => "") |> decode_crockford_base32
    return track_vote(server, proposal, code_bytes)
end


SERVER = URI("http://127.0.0.1:4584")
PROPOSAL = UUID("49e9ebce-fb9e-5b83-1534-75cff3ee423a")

