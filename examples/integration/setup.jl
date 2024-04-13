module IntegrationSetup

# This module sets up integration for PeaceFounderAdmin
# To use it include this file before starting the PeaceFounderAdmin server

import PeaceFounderAdmin

using Oxygen: json, Request, Response
import PeaceFounder.Server.Service: @get, @put, @post, ROUTER # @delete

import PeaceFounder.Core.Model: TicketID
import PeaceFounder.Server.Mapper

import PeaceFounder.Authorization: AuthServerMiddleware, timestamp
using Dates: DateTime, now, Second


@post "/registrar" function(req::Request)
    
    if abs(now() - timestamp(req)) > Second(5) 
        return Response(400, "Request arrived too late")
    end

    key = Mapper.token_key()
    credential = "registrar" # It could be beneficial to derive it from key

    handler = AuthServerMiddleware(credential, key) do req

        (; name, email, tid) = json(req)

        ticketid = TicketID(hex2bytes(tid))
        PeaceFounderAdmin.create_profile(name, email, ticketid)
        
        invite = Mapper.enlist_ticket(ticketid) 

        (; demehash, hasher, route) = invite
        (; demehash, hasher, route = string(route)) |> json
    end

    return handler(req)
end


end
