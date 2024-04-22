import HTTP
using Dates

using JSON3 
using StructTypes

import PeaceFounder.Core: Parser, ProtocolSchema
import PeaceFounder.Core.Model: Digest 
import PeaceFounder.Core.ProtocolSchema: Invite
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

    registration_index = get_registration_index(Mapper.BRAID_CHAIN[], ticketid)

    if isnothing(registration_index)

        try

            admission_state = ProtocolSchema.isadmitted(ticketid, Mapper.REGISTRAR[]) # arguments could be reverse
            
            if !admission_state
                return Invited(false)
            else
                return Admitted(false)
            end

        catch
            
            # it is uknonw at this point whether client already had obtained an admission
            # the safest option is to say it is expired. In case ticket is renewed and dublicate 
            # admission is issued we rely on braidchain to drop memebership registrations with the same ticketid
            
            return Invited(true) 
        end
    end

    # To check if profile is verified we need to go through ElectoralRoll and check attribute for the profile 
    
    # One could proceed looking termination transaction in future
    return Registered(registration_index, false)
end


mutable struct MemberProfile
    name::String
    email::String
    ticketid::TicketID # I could consider moving TicketID -> UUID; TicketID though is more versatile as it can encode information.
    created::DateTime # 
end

MemberProfile(name::String, email::String, ticket::TicketID) = MemberProfile(name, email, ticket, Dates.now(UTC))

StructTypes.StructType(::Type{MemberProfile}) = StructTypes.Struct()

Base.isless(x::MemberProfile, y::MemberProfile) = isless(x.created, y.created)

struct ElectoralRoll
    ledger::Vector{MemberProfile}
end

Base.push!(roll::ElectoralRoll, profile::MemberProfile) = push!(roll.ledger, profile)
Base.sort!(roll::ElectoralRoll) = sort!(roll.ledger)

ElectoralRoll() = ElectoralRoll(MemberProfile[])


ELECTORAL_ROLL::ElectoralRoll = ElectoralRoll()
REGISTRAR_PATH::String = ""


function store(profile::MemberProfile, path::String)
    mkpath(dirname(path))
    open(path, "w") do file
        JSON3.write(file, profile)
    end
end

function load(::Type{MemberProfile}, path::String)
    return open(path, "r") do file
        return JSON3.read(file, MemberProfile)
    end
end

function store(roll::ElectoralRoll, dir::String)
    for profile in roll.ledger
        ticketid = string(profile.ticketid)
        mkpath(joinpath(dir, ticketid))
        store(profile, joinpath(dir, ticketid, "metadata.json"))
    end
end

function load(::Type{ElectoralRoll}, dir::String)

    roll = ElectoralRoll()

    isdir(dir) || return roll # return empty collection if directory does not exist

    for profile_path in readdir(dir)
        profile = load(MemberProfile, joinpath(dir, profile_path, "metadata.json"))
        push!(roll, profile)
    end
    
    sort!(roll)

    return roll
end

function store(profile::MemberProfile)
    isempty(REGISTRAR_PATH) && return
    store(profile, joinpath(REGISTRAR_PATH, "records", string(profile.ticketid), "metadata.json"))
end

load(::Type{MemberProfile}, ticketid::TicketID) = load(MemberProfile, joinpath(REGISTRAR_PATH, "records", string(ticketid), "metadata.json"))


function evict(ticketid::TicketID)

    roll_index = findfirst(x -> x.ticketid == ticketid, ELECTORAL_ROLL.ledger)
    deleteat!(ELECTORAL_ROLL.ledger, roll_index)

    try
        Mapper.delete_ticket(ticketid)
    catch
        @warn "If admission is issued bur member is only about to register then it will be orphaned. The record will be moved in `registrar/evictees` if needed for recovery."
    end
    
    if !isempty(REGISTRAR_PATH) && isdir(joinpath(REGISTRAR_PATH, "records", string(ticketid)))

        mkpath(joinpath(REGISTRAR_PATH, "evictees"))
        mv(joinpath(REGISTRAR_PATH, "records", string(ticketid)), joinpath(REGISTRAR_PATH, "evictees", string(ticketid)))

    end

    return
end


function create_profile(name::String, email::String, ticketid::TicketID)

    for member in ELECTORAL_ROLL.ledger
        if member.ticketid == ticketid
            return member
        end
    end
    
    member = MemberProfile(name, email, ticketid)

    push!(ELECTORAL_ROLL, member)
    store(member)

    return member
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

    push!(ELECTORAL_ROLL, member)
    store(member)

    return member
end


function Base.get(null::Function, roll::ElectoralRoll, ticketid::TicketID)

    for member in roll.ledger
        if member.ticketid == ticketid
            return member
        end
    end

    return null()
end



struct MemberProfileView
    TICKETID::String # This is good to have for intermediate actions, I could also try TicketID
    NAME::String
    EMAIL::String
    TIMESTAMP::String 
    REGISTRATION::String # Can be HTML and etc. Whatever works here
    STATUS::String
end


function construct_view(profile::MemberProfile, state::MemberState = get_registration_status(profile.ticketid))

    (; name, email, ticketid, created) = profile

    NAME = name
    EMAIL = email
    TICKETID = bytes2hex(ticketid)


    TIMESTAMP = Dates.format(created |> local_time, "d u yyyy, HH:MM")

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

    #update!(ELECTORAL_ROLL)

    profiles = MemberProfileView[construct_view(i) for i in ELECTORAL_ROLL.ledger]
    
    #return render(joinpath(TEMPLATES, "registrar.html"), Dict("TABLE"=>profiles)) |> html
    
    return render_template("registrar.html") <| [
        :TABLE => profiles
    ]
end


function send(invite::Invite, profile::MemberProfile)

    (; name, email) = profile

    invite_code = String(Parser.marshal(invite))

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
    evict(ticketid)
    
    return Response(301, Dict("Location" => "/registrar"))
end


@put "/registrar/{tid}" function(req::Request, tid::String)

    ticketid = TicketID(hex2bytes(tid))

    profile = get(ELECTORAL_ROLL, ticketid) do
        error("Wrong TicketID")
    end

    invite = Mapper.enlist_ticket(profile.ticketid, reset=true) 

    send(invite, profile)

    return Response(301, Dict("Location" => "/registrar"))
end

