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
    timestamp::Union{DateTime, Nothing}

    Invited() = new(true, nothing)
    Invited(expired::Bool, timestamp::DateTime) = new(expired, timestamp)
end 

struct Admitted <: MemberState 
    expired::Bool
    timestamp::DateTime
end

struct Registered <: MemberState
    index::Int # registerd
    # invited::Union{DateTime, Nothing}
    admitted::DateTime # for registration, it may make sense to put timestamps in as an vector
    registered::DateTime
    verified::Union{DateTime, Nothing}
    
    Registered(index::Int, admitted::DateTime, registered::DateTime) = new(index, admitted, registered, nothing)
    Registered(state::Registered, verified::DateTime) = new(state.index, state.admitted, state.registered, verified)
end

struct Terminated <: MemberState
    rindex::Int
    tindex::Int
    admitted::DateTime
    registered::DateTime
    verified::Union{DateTime, Nothing} # May never have been verified
    terminated::DateTime
    
    Terminated(rindex::Int, tindex::Int, admitted::DateTime, registered::DateTime, terminated::DateTime; verified = nothing) = 
        new(rindex, tindex, admitted, registered, verified, terminated)
    Terminated(state::Terminated, verified::DateTime) = new(state.rindex, state.tindex, state.admitted, state.registered, verified, state.terminated)
end


function get_registration_index(null::Function, chain, ticketid::TicketID)

    for (i, record) in enumerate(chain.ledger)
        if record isa Membership && record.admission.ticketid == ticketid
            return i
        end
    end

    return null()
end

function get_termination_index(null::Function, chain, identity::Pseudonym)

    for (i, record) in enumerate(chain.ledger)
        if record isa Termination && record.identity == identity
            return i
        end
    end

    return null()
end

function must_throw(null::Function)
    return function ()
        null()
        error("Null must throw in the context")
    end
end
    
function get_registration_state_chain(null::Function, chain, ticketid::TicketID)

    # Here it would be necessary to throw to a parrent
    # index = get_registration_index(@parent null, chain, ticketid)
    index = get_registration_index(must_throw(null), chain, ticketid) # the null does not compose as I still need to return from the call stack
    
    record = chain[index]

    admission_timestamp = record.admission.seal.timestamp
    registration_timestamp = record.approval.timestamp

    # term_index = @promote_return get_termination_index(chain, ticketid) do
    #     return Registered(index, admission_timestamp, registration_timestamp)
    # end
    term_index = get_termination_index(chain, id(record)) do
        return nothing # annoingly there is no parrent return 
    end

    if isnothing(term_index)
        return Registered(index, admission_timestamp, registration_timestamp)
    else
        term_record = chain[term_index]
        termination_timestamp = term_record.seal.timestamp
        return Terminated(index, term_index, admission_timestamp, registration_timestamp, termination_timestamp)
    end
end

# This code is an experimentation for a situation if there were a parent return
# no performance of this code is expected 
# An example how this function would look like with @promote_return macro
# function get_registration_status(ticketid::TicketID)
#     return @promote_return get_registration_state_chain(Mapper.BRAID_CHAIN[], ticketid) do

#         ticket = get(Mapper.REGISTRAR[], ticketid) do
#             @warn "Ticket not in registrar; Perhaps the system have been reset during member registration"
#             return Invited()
#         end
        
#         if isnothing(ticket.admission)
#             return Invited(false, ticket.timestamp)
#         else
#             return Admitted(false, ticket.admission.seal.timestamp)
#         end
#     end
# end
function get_registration_status(ticketid::TicketID)
    try return get_registration_state_chain(Mapper.BRAID_CHAIN, ticketid) do

        ticket = get(Mapper.REGISTRAR, ticketid) do

            # it is uknonw at this point whether client already had obtained an admission
            # the safest option is to say it is expired. In case ticket is renewed and dublicate 
            # admission is issued we rely on braidchain to drop memebership registrations with the same ticketid
            
            @warn "Ticket not in registrar; Perhaps the system have been reset during member registration"
            throw(Invited()) # the value would need to be thrown in a wrapping
        end
        
        if isnothing(ticket.admission)
            throw(Invited(false, ticket.timestamp))
        else
            throw(Admitted(false, ticket.admission.seal.timestamp))
        end
    end catch value
        if value isa MemberState # For a generic case I would need boxing here
            return value
        else
            rethrow(value)
        end
    end
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

    # We also need to consider orphaned records from the braidchain ledger to recover from a failure
    # There is also possibility that an orphaned record is about to be created

    return roll
end

function store(profile::MemberProfile)
    isempty(REGISTRAR_PATH) && return
    store(profile, joinpath(REGISTRAR_PATH, "records", string(profile.ticketid), "metadata.json"))
end

load(::Type{MemberProfile}, ticketid::TicketID) = load(MemberProfile, joinpath(REGISTRAR_PATH, "records", string(ticketid), "metadata.json"))


function get_admission(registrar, ticketid)
    ticket = get(registrar, ticketid) do
        error("Ticket $ticketid not found") # 
    end

    return ticket.admission
end


function evict_electoral_roll_entry(ticketid)

    roll_index = findfirst(x -> x.ticketid == ticketid, ELECTORAL_ROLL.ledger)
    deleteat!(ELECTORAL_ROLL.ledger, roll_index)
    
    if !isempty(REGISTRAR_PATH) && isdir(joinpath(REGISTRAR_PATH, "records", string(ticketid)))

        mkpath(joinpath(REGISTRAR_PATH, "evictees"))
        mv(joinpath(REGISTRAR_PATH, "records", string(ticketid)), joinpath(REGISTRAR_PATH, "evictees", string(ticketid)))

    end

    return
end

function evict(ticketid::TicketID)

    status = get_registration_status(ticketid)

    if status isa Invited

        Mapper.delete_ticket(ticketid) do
            @warn "If admission is issued but member is only about to register then it will be orphaned. The record will be moved in `registrar/evictees` if needed for recovery."
        end
           
        evict_electoral_roll_entry(ticketid)
        
    elseif status isa Admitted

        admission = get_admission(Mapper.REGISTRAR, ticketid)
        termination = Termination(id(admission)) |> approve(Mapper.REGISTRAR.signer)
        Mapper.submit_chain_record!(termination)

        evict_electoral_roll_entry(ticketid)

    elseif status isa Registered
        
        record = Mapper.get_chain_record(status.index)
        termination = Termination(status.index, id(record)) |> approve(Mapper.REGISTRAR.signer)
        Mapper.submit_chain_record!(termination)

    elseif status isa Terminated
        error("A member with $ticketid already terminated")
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
    ACTION::String
end


function construct_view(profile::MemberProfile, state::MemberState = get_registration_status(profile.ticketid))

    (; name, email, ticketid, created) = profile

    NAME = name
    EMAIL = email
    TICKETID = bytes2hex(ticketid)

    TIMESTAMP = Dates.format(created |> local_time, "d u yyyy, HH:MM")

    td_actions(str) = """
        <td style="text-align: right; width: 70px; padding-top:5px; padding-bottom:0;"><span class="fw-normal" >$str</span></td>
    """

    if state isa Invited

        STATUS = """<span class="fw-bold">Invited</a>"""

        if state.expired
            REGISTRATION = """<span class="fw-bold text-danger">Expired</a>"""
        else
            REGISTRATION = """<span class="fw-bold text-success">Pending</a>"""
        end

        ACTION = """
    <button class="btn btn-sm btn-outline-secondary" type="button" onclick="sendSignal('registrar/$TICKETID', 'PUT');">Retry</button>
    <button class="btn btn-sm btn-outline-danger"  type="button" onclick="sendSignal('registrar/$TICKETID', 'DELETE');">Abort</button>

    """ |> td_actions

    elseif state isa Admitted

        STATUS = """<span class="fw-bold text-warning">Admitted</a>"""

        if state.expired

            REGISTRATION = """<span class="fw-bold text-danger">Admitted-Expired</a>"""
            STATUS = STATUS_ACTIONS

        else

            REGISTRATION = """<span class="fw-bold text-success">Pending</a>"""
            STATUS = """<span class="fw-bold">Admitted</span>"""

        end

        ACTION = """
           <button class="btn btn-sm btn-outline-danger"  type="button" onclick="sendSignal('registrar/$TICKETID', 'DELETE');">Abort</button>
        """ |> td_actions

    elseif state isa Registered
        
        REGISTRATION = string(state.index)

        if !isnothing(state.verified)
            STATUS = """<span class="fw-bold text-success">Verified</span>"""
        else
            STATUS = """<span class="fw-bold">Trial</span>"""
        end

        ACTION = """<button class="btn btn-sm btn-outline-danger"  type="button" onclick="sendSignal('registrar/$TICKETID', 'DELETE');">Terminate</button>""" |> td_actions

    elseif state isa Terminated

        REGISTRATION = string(state.rindex)

        terminated = Dates.format(state.terminated |> local_time, "d u yyyy, HH:MM")

        STATUS = """<span class="fw-bold">Terminated</span>"""
        ACTION = """<td style="text-align: right; width: 70px;"><span class="fw-normal" ><span>$terminated</span></td>"""

    end

    

    return MemberProfileView(TICKETID, NAME, EMAIL, TIMESTAMP, REGISTRATION, STATUS, ACTION)
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

