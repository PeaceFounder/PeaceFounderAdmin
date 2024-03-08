# Need to refactor to use DemeAccount directly

using Infiltrator
using Oxygen
using HTTP: Request

using PeaceFounder: Client, Parser
using PeaceFounder.Model: Selection
using PeaceFounder.Client: Invite, DemeClient

# Reseting a state here is more burdensome
isdefined(Main, :Clients) || (CLIENTS = [])

function register(invite::Invite)

    client = Client.DemeClient()
    Client.enroll!(client, invite)
    #(uuid, index) = Client.enroll!(client, invite)
    #global UUID = uuid # assuming all are the same
    
    push!(CLIENTS, client)
end

register(invite::String) = register(PeaceFounder.Parser.unmarshal(invite, Invite))

@post "/debug" function(req::Request)

    @infiltrate

    invite = Parser.unmarshal(req.body, Invite)
    register(invite)

    return
end


get_index(client::DemeClient) = client.accounts[1].guard.ack.proof.index
get_deme_uuid(client::DemeClient) = client.accounts[1].deme.uuid


function get_client(member::Int)

    for client in CLIENTS
        if get_index(client) == member
            return client
        end
    end

    error("Client with index $member not found")
end


function vote(proposal::Int, member::Int, selection::Selection)
    
    # find the member
    # update cache
    # 
    client = get_client(member)

    uuid = get_deme_uuid(client)    
    Client.update_deme!(client, uuid)
    
    Client.cast_vote!(client, uuid, proposal, selection)    

    return
end

vote(proposal::Int, member::Int, selection::Int) = vote(proposal, member, Selection(selection))


isdefined(Main, :service) && close(service)
#global service = Oxygen.serve(host="0.0.0.0", port=3342, async=true)
global service = Oxygen.serve(host="0.0.0.0", port=3342)

