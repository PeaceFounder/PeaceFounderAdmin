import HTTP
using Dates

import PeaceFounder.Model: Registrar, Digest, Ticket, token, hmac
import PeaceFounder.Client: Invite
using URIs


# MemberState is something like an Union type here.
abstract type MemberState end

struct Invited <: MemberState 
    expired::Bool
end 

struct Admitted <: MemberState 
    expired::Bool
end

struct Registered <: MemberState
    registered::Int
    #index::Int
    verified::Bool
end

struct Terminated <: MemberState
    registered::Int
    terminated::Int
end


function get_registration_index(chain, ticketid::TicketID)

    for (i, record) in enumerate(chain.ledger)
        if record isa Membership && record.admission.ticketid == ticketid
            return i
        end
    end

    return nothing
end


function get_registration_status(ticketid::TicketID)

    admission_state = PeaceFounder.Model.isadmitted(ticketid, PeaceFounder.Mapper.REGISTRAR[])

    if !admission_state
        return Invited(false)
    end

    registration_index = get_registration_index(PeaceFounder.Mapper.BRAID_CHAIN[], ticketid)

    if isnothing(registration_index)
        return Admitted(false)
    end

    # One could proceed looking termination transaction in future
    return Registered(registration_index, false)
end


mutable struct MemberProfile
    name::String
    email::String
    ticketid::TicketID
    created::DateTime # 
    state::MemberState
    #index::Union{Int, Nothing}
    #termination::Union{Int, Nothing} # Refers to braidchain
end

MemberProfile(name::String, email::String, ticket::TicketID) = MemberProfile(name, email, ticket, Dates.now(), Invited(false))

#@enum MemberState 

struct ElectoralRoll
    ledger::Vector{MemberProfile}
end

ElectoralRoll() = ElectoralRoll(MemberProfile[])

const ELECTORAL_ROLL = ElectoralRoll()


update!(profile::MemberProfile) = profile.state = get_registration_status(profile.ticketid)

function update!(roll::ElectoralRoll)

    for profile in roll.ledger
        try
            update!(profile) 
        catch
            @warn "$(profile.name) can't be updated"
        end
    end

    return
end


# This is registered in a roll
function create_profile(name::String, email::String)

    if email != "DEBUG" && !startswith(email, "http://")
        for member in ELECTORAL_ROLL.ledger
            if member.email == email
                #return member.ticketid
                return member
            end
        end
    end

    # registers the email

    ticketid = TicketID(rand(UInt8, 16))
    member = MemberProfile(name, email, ticketid)

    push!(ELECTORAL_ROLL.ledger, member)

    return member
end


function get(roll::ElectoralRoll, ticketid::TicketID)

    for member in roll.ledger
        if member.ticketid == ticketid
            return member
        end
    end

    return nothing
end





struct MemberProfileView
    TICKETID::String # This is good to have for intermediate actions, I could also try TicketID
    NAME::String
    EMAIL::String
    TIMESTAMP::String 
    REGISTRATION::String # Can be HTML and etc. Whatever works here
    STATUS::String
end


function construct_view(profile::MemberProfile)

    (; name, email, ticketid, created, state) = profile

    NAME = name
    EMAIL = email
    TICKETID = bytes2hex(ticketid)


    TIMESTAMP = Dates.format(created, "d u yyyy, HH:MM")

    STATUS_ACTIONS = """
<td style="padding-top:5px; padding-bottom:0;">
<button class="btn btn-sm btn-outline-danger" style="margin-right: 5px;" type="button" onclick="sendSignal('registrar/$TICKETID', 'DELETE');">Cancel</button>
<button class="btn btn-sm btn-outline-primary" type="button" onclick="sendSignal('registrar/$TICKETID', 'PUT');">Retry</button></td>
        """

    if state isa Invited

        STATUS = STATUS_ACTIONS

        if state.expired
            REGISTRATION = """<a href="#" class="fw-bold text-danger">Invited-Expired</a>"""
        else
            REGISTRATION = """<a href="#" class="fw-bold text-success">Invited</a>"""
        end

    elseif state isa Admitted

        if state.expired

            REGISTRATION = """<a href="#" class="fw-bold text-danger">Admitted-Expired</a>"""
            STATUS = STATUS_ACTIONS

        else

            REGISTRATION = """<a href="#" class="fw-bold text-success">Admitted</a>"""
            STATUS = """<td><span class="fw-bold">Pending</span></td>"""

        end

    elseif state isa Registered
        
        REGISTRATION = string(state.registered)

        if state.verified
            STATUS = """<td><span class="fw-bold text-success">Verified</span></td>"""
        else
            STATUS = """<td><span class="fw-bold text-warning">Trial</span></td>"""
        end

    elseif state isa Terminated

        REGISTRATION = string(state.registered)
        STATUS = """<td><span class="fw-bold text-danger">Terminated</span></td>"""

    end

    return MemberProfileView(TICKETID, NAME, EMAIL, TIMESTAMP, REGISTRATION, STATUS)
end

@get "/registrar" function(req::Request)

    update!(ELECTORAL_ROLL)

    profiles = MemberProfileView[construct_view(i) for i in ELECTORAL_ROLL.ledger]
    
    return render(joinpath(TEMPLATES, "registrar.html"), Dict("TABLE"=>profiles)) |> html
end


function send(invite::Invite, profile::MemberProfile)

    (; name, email) = profile

    invite_code = String(PeaceFounder.Parser.marshal(invite))

    spec = Mapper.get_demespec()

    invite_rendered = Mustache.render(SETTINGS.INVITE_TEXT, Dict("INVITE"=>invite_code, "NAME"=>name, "DEME"=>spec.title))
    
    
    body = """
    From: $(SETTINGS.SMTP_EMAIL)
    To: $email
    Subject: $(SETTINGS.INVITE_SUBJECT)
    $invite_rendered
    """
    
    if email=="DEBUG" # consider as a debug case

        println(body)

    elseif startswith(email, "http://")
        
        @infiltrate

        address = email

        HTTP.post(address; body=invite_code)

        println("Invite sent to debug address: $address")
    else
        opt = SMTPClient.SendOptions(isSSL = true, username = SETTINGS.SMTP_EMAIL, passwd = SETTINGS.SMTP_PASSWORD)
        SMTPClient.send(SETTINGS.SMTP_SERVER, [email], SETTINGS.SMTP_EMAIL, IOBuffer(body), opt)
    end

end


@post "/registrar" function(req::Request)

    # Let's do this
    (; name, email) = json(req)

    profile = create_profile(name, email)
    invite = Mapper.enlist_ticket(profile.ticketid)

    send(invite, profile)

    return Response(301, Dict("Location" => "/registrar"))    
end


@delete "/registrar/{tid}" function(req::Request, tid::String)

    ticketid = TicketID(hex2bytes(tid))

    Mapper.delete_ticket(ticketid)

    roll_index = findfirst(x -> x.ticketid == ticketid, ELECTORAL_ROLL.ledger)
    deleteat!(ELECTORAL_ROLL.ledger, roll_index)

    return Response(301, Dict("Location" => "/registrar"))
end


@put "/registrar/{tid}" function(req::Request, tid::String)

    ticketid = TicketID(hex2bytes(tid))

    profile = get(ELECTORAL_ROLL, ticketid)
    invite = Mapper.enlist_ticket(profile.ticketid, reset=true) 

    send(invite, profile)

    return Response(301, Dict("Location" => "/registrar"))
end

