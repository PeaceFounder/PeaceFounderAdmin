module InviteCode

using Nettle
using URIs: URI
using Base64: base64encode
using PeaceFounder.Authorization: AuthClientMiddleware # This will be in a seperate package in the future
using HTTP: HTTP, Request, Response, Router
using JSON3

global TOKEN_KEY::Vector{UInt8}
global TOKEN_LENGTH::Int

function base64encode_url(bytes::Vector{UInt8})
    str = base64encode(bytes)
    newstr = replace(str, '+'=>'-', '/'=>'_')
    return rstrip(newstr, '=')
end

function invite_str(hash_spec::String, demehash::Vector{UInt8}, route::URI, token::Vector{UInt8})

    hash_str = demehash |> base64encode_url
    token_str = token |> base64encode_url
    
    if route == URI()
        return "deme:?xt=$hash_spec:$hash_str&tk=$token_str"
    else
        return "deme:?xt=$hash_spec:$hash_str&sr=$route&tk=$token_str"
    end
end

function invite_str(resp::Response, ticketid::Vector{UInt8}; attempt = UInt8(0))

    (; demehash, hasher, route) = JSON3.read(resp.body)

    demehash_bytes = hex2bytes(demehash)
    _token = Nettle.digest(hasher, UInt8[TOKEN_KEY..., attempt, ticketid...])[1:TOKEN_LENGTH]    

    return invite_str(hasher, demehash_bytes, URI(route), _token)
end

request(router::Router, req::Request) = router(req)
request(url::URI, req::Request) = HTTP.request(req.method, URI(url; path = req.target), req.headers, req.body)

host(router::Router) = ""
host(url::URI) = string(url)

function create_profile(server::Union{Router, URI}, name::String, email::String, ticketid::Vector{UInt8})
    
    body = JSON3.write((; name, email, tid = bytes2hex(ticketid)))
    req = Request("POST", "/registrar", ["Host" => host(server)], body)

    handler = AuthClientMiddleware(req -> request(server, req), "registrar", TOKEN_KEY)
    resp = handler(req)

    return invite_str(resp, ticketid)
end

end
