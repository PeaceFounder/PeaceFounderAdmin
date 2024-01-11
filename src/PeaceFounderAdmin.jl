module PeaceFounderAdmin

# This code is written intentionally bad, aimed at rapid development and overcoming creative blocks. 
# It prioritizes speed and exploratory programming over best coding practices. 
# It is not intended for production use and may contain inefficiencies and unconventional methods. 
# Use this code as a starting point or for inspiration, rather than as a standard of quality.

using Oxygen
using HTTP: Request, Response
import HTTP
using Mustache
using Infiltrator
using PeaceFounder

using UUIDs

using PeaceFounder.Model: CryptoSpec, pseudonym, TicketID, Member, Proposal, Ballot, Selection, generator, state, id, vote, seed, tally, approve, istallied, DemeSpec, hasher, HMAC, auth, token, isbinding, Generator, generate, Signer


import SMTPClient

# 
SERVER_PORT = Ref(4584)

TEMPLATES = joinpath(dirname(@__DIR__), "templates")
dynamicfiles(joinpath(dirname(@__DIR__), "public"), "/") # Static files would also be fine here

# This should be part of the mapper
const PROPOSER = Ref{Signer}()

const DEMESPEC_CANDIDATE = Ref{DemeSpec}()

const SETTINGS = Dict{String, String}()

const SETTINGS_DEFAULT = Dict{String, String}()


# The device will perform a following steps:
#   - The device will retrieve deme specification parameters from provided address which will be compared with sotored hash in the invite
#   - The cryptographic parameters will be initialised and a new key pair generated.
#   - The public key will be authetificated with HMAC using the invite tooken and will be sent to the deme server which shall return the ppublic key signed by the registrar which whe shall reffer as admission certificate.
#   - In the last step device retrieves the current braidchain generator and computes it's pseudonym. This together with admission certificate is signed by the member's private key which consistutes a member certificate. The member certificate is sent to the braidchain until History Tree inclusion proof is received concluding the process. If generator has changed a new pseudonym is recomputed.


SETTINGS_DEFAULT["SMTP_EMAIL"] = ""
SETTINGS_DEFAULT["SMTP_PASSWORD"] = ""
SETTINGS_DEFAULT["SMTP_SERVER"] = ""

SETTINGS_DEFAULT["INVITE_DEME_ADDRESS"] = "http://127.0.0.1:$(SERVER_PORT[])"
SETTINGS_DEFAULT["INVITE_SUBJECT"] = "Membership Invite to Deme"
SETTINGS_DEFAULT["INVITE_TEXT"] = 
"""
Dear {{{NAME}}},

To begin your journey with PeaceFounder, simply launch the PeaceFounder client on your device and enter the invite code shown below. The rest of the process will be handled automatically by your device.

{{{INVITE}}}

Once registered, on your device you'll see a registration index, indicating your membership certificate's inclusion in BraidChain ledger. This index confirms your successful registration.

For auditing and legitimacy, please send a document within two weeks listing your registration index and the invite code, signed with your digital identity provider. Note that failure to complete this step will result in membership termination.

Guardian
{{DEME}}\
"""

function reset()

    for key in keys(SETTINGS_DEFAULT)
        SETTINGS[key] = SETTINGS_DEFAULT[key]
    end

    return
end

reset()

iscaptured() = isassigned(Mapper.BRAID_CHAIN)


function create_deme((; title, email, group, hash, password))

    @warn "Email field unimplemented"
    @warn "Guardian private key encryption unimplemented and won't be stored"

    # group and hash needs to come in here
    crypto = CryptoSpec(hash, group)

    guardian = generate(Signer, crypto)
    PROPOSER[] = generate(Signer, crypto)
    
    Mapper.initialize!(crypto)

    roles = Mapper.system_roles()
 
    DEMESPEC_CANDIDATE[] = DemeSpec(;
                        uuid = UUIDs.uuid4(),
                        title = title,
                        crypto = crypto,
                        guardian = id(guardian),
                        recorder = roles.recorder,
                        recruiter = roles.recruiter,
                        braider = roles.braider,
                        proposer = id(PROPOSER[]),
                        collector = roles.collector
                        ) |> approve(guardian)
    
    return
end


using Gumbo
using Cascadia

# This is in fact the only method I need
function get_option_text(fname, value)

    html_str = read(fname, String)

    parsed_html = parsehtml(html_str)

    options = eachmatch(Selector("option"), parsed_html.root)

    for option in options
        if (value == option.attributes["value"])
            return strip(nodeText(option))
        end
    end

    error("$fname does not have an option with $value")
end

function chunk_string(s::String, chunk_size::Int)
    return join([s[i:min(i+chunk_size-1, end)] for i in 1:chunk_size:length(s)], " ")
end

function render(fname, args...; kwargs...)
    
    dir = pwd()
    
    try
        cd(dirname(fname))

        tmpl = Mustache.load(fname)
        return Mustache.render(tmpl, args...; kwargs...)
        
    finally
        cd(dir)
    end
end


@get "/setup" function(req::Request)

    tmp = Mustache.load(joinpath(TEMPLATES, "wizard-step-1.html"))

    return Mustache.render(tmp) |> html
end


@get "/configurator" function(req::Request)

    return render(joinpath(TEMPLATES, "wizard-step-2a.html")) |> html
end


@post "/configurator" function(req::Request)
    
    create_deme(json(req))

    return
end


#formatted_string = format_string("027080e9ac7055cfd26d06ccd017daa5a4206454b65d6645d3", 8)


@get "/setup-summary" function(req::Request)

    (; uuid, title, crypto, guardian, recorder, recruiter, braider, proposer, collector) = DEMESPEC_CANDIDATE[]

    # Title first
    tmpl = Mustache.load(joinpath(TEMPLATES, "wizard-step-3.html"))

    group_name = get_option_text(joinpath(TEMPLATES, "partials/group_specs.html"), PeaceFounder.Model.lower_groupspec(crypto.group))
    hash_name = get_option_text(joinpath(TEMPLATES, "partials/hash_specs.html"), string(crypto.hasher))
    
    guardian_pbkey = chunk_string(string(guardian), 8) #|> uppercase

    # For this one I would need to do key maangement manually
    #roles = raw"<b>BraidChain</b>, <s>BallotBox</s>, <b>Registrar</b>, <s>Proposer</s>, <s>Braider</s>"
    roles = raw"<b>BraidChain</b>, <b>BallotBox</b>, <b>Registrar</b>, <b>Proposer</b>, <b>Braider</b>"
    commit = "#1"

    return Mustache.render(tmpl; title, uuid, group_name, hash_name, guardian_pbkey, roles, commit) |> html
end 


@post "/setup-summary" function(req::Request)

    Mapper.capture!(DEMESPEC_CANDIDATE[])

    return Response(302, Dict("Location" => "/")) # One wants to be sure that it indeed works
end


############################ WIZARD ENDS #######################

hassmtp() = !isempty(SETTINGS["SMTP_EMAIL"]) && !isempty(SETTINGS["SMTP_SERVER"]) && !isempty(SETTINGS["SMTP_PASSWORD"])

@get "/" function(req::Request)

    if !iscaptured()
        return Response(302, Dict("Location" => "/setup"))
    elseif !hassmtp()
        return Response(302, Dict("Location" => "/settings"))
    else
        return Response(302, Dict("Location" => "/status"))
    end
end


@get "/settings" function(req::Request)

    return render(joinpath(TEMPLATES, "settings.html"), SETTINGS) |> html
end

@get "/status" function(req::Request)

    demespec = Mapper.BRAID_CHAIN[][1] # keep it simple

    DATA = Dict{String, String}()

    DATA["UUID"] = string(demespec.uuid)
    DATA["TITLE"] = demespec.title

    return render(joinpath(TEMPLATES, "status.html"), DATA) |> html
end


function test_smtp((; email))

    from = SETTINGS["SMTP_EMAIL"]

    body = """
    From: $from
    To: $email
    Subject: This is a SMTP Test

    Hello World!!!

    Deme Server
    """

    opt = SMTPClient.SendOptions(isSSL = true, username = SETTINGS["SMTP_EMAIL"], passwd = SETTINGS["SMTP_PASSWORD"])
    SMTPClient.send(SETTINGS["SMTP_SERVER"], [email], SETTINGS["SMTP_EMAIL"], IOBuffer(body), opt)

    return
end


@post "/settings/smtp-test" function(req::Request)
    
    test_smtp(json(req))

    return Response(302, Dict("Location" => "/settings")) # I could do an error in similar way
end


@post "/settings/smtp" function(req::Request)

    (; email, password, server) = json(req)

    SETTINGS["SMTP_EMAIL"] = email
    SETTINGS["SMTP_PASSWORD"] = password # One can spend quite a time to get this working
    SETTINGS["SMTP_SERVER"] = server

    return 
end


@post "/settings/invite" function(req::Request)

    (; address, time, subject, text) = json(req)

    SETTINGS["INVITE_DEME_ADDRESS"] = address
    SETTINGS["INVITE_SUBJECT"] = subject
    SETTINGS["INVITE_TEXT"] = text

    return
end



using Dates

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
        if record isa Member && record.admission.ticketid == ticketid
            return i
        end
    end

    return nothing
end


function get_registration_status(ticketid::TicketID)

    admission_state = PeaceFounder.Model.isadmitted(ticketid, PeaceFounder.Mapper.RECRUITER[])

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



# TokenRecruiter is responsable Shift + \ users can configgure keyboard to `Option + \`
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
# sort by indexv

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



import PeaceFounder.Model: TokenRecruiter, Digest, Ticket, token, hmac

# Need to included in the Model
function enlist_locally!(recruiter::TokenRecruiter, ticketid::TicketID, timestamp::DateTime)

    @assert (Dates.now() - timestamp) < Second(60) "Request too old"

    for ticket in recruiter.tickets
        if ticket.ticketid == ticketid
            return ticket.token
        end
    end

    # Seems as unnecessary complication
    salt = rand(UInt8, 16)
    _token = token(ticketid, salt, hmac(recruiter))    

    push!(recruiter.tickets, Ticket(ticketid, timestamp, salt, Digest([]), _token, nothing))

    return _token
end

# This has part in the Mapper
enlist_locally!(ticketid::TicketID, timestamp::DateTime) = enlist_locally!(PeaceFounder.Mapper.RECRUITER[], ticketid, timestamp) # returns a token


# tid = TicketID("Hello")

# t = enlist_locally!(tid, Dates.now())

import PeaceFounder.Client: Invite

#demespec = PeaceFounder.Mapper.BRAID_CHAIN[].ledger[1]
#demehash = PeaceFounder.Model.digest(demespec, demespec.crypto)


using URIs

#DEME_ADDRESS = # Neeed to get that from a socket

#invite = Invite(demehash, tid, t, demespec.crypto.hasher, URI(SETTINGS["DEME_SERVER_ADDRESS"]))

#member == get(ELECTORAL_ROLL, ticketid)::MemberProfile # If nothing throws an error here

# Seperation necessary to accomodate repeated sending
#function create_invite(ticketid::TicketID) # Can be created from a string

function create_invite(profile::MemberProfile) # Can be created from a string
    
    (; ticketid, created) = profile

    token = enlist_locally!(ticketid, created) 
    #token = enlist_locally!(ticketid, Dates.now()) # 

    demespec = PeaceFounder.Mapper.BRAID_CHAIN[].ledger[1]
    demehash = PeaceFounder.Model.digest(demespec, demespec.crypto)
    
    invite = Invite(demehash, ticketid, token, demespec.crypto.hasher, URI(SETTINGS["INVITE_DEME_ADDRESS"]))

    return invite
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
    #TIMESTAMP = Dates.format(created, "yyyy-u-dd HH:MM")

    #TIMESTAMP = Dates.format(created, "u dd, yyyy, HH:MM")

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

    spec = Mapper.BRAID_CHAIN[].ledger[1]

    invite_rendered = Mustache.render(SETTINGS["INVITE_TEXT"], Dict("INVITE"=>invite_code, "NAME"=>name, "DEME"=>spec.title))

    from = SETTINGS["SMTP_EMAIL"]
    subject = SETTINGS["INVITE_SUBJECT"]
    
    body = """
    From: $from
    To: $email
    Subject: $subject
    $invite_rendered
    """
    
    if email=="DEBUG" # consider as a debug case

        println(body)

    elseif startswith(email, "http://")
        
        address = email

        HTTP.post(address; body=invite_code)

        println("Invite sent to debug address: $address")
    else
        opt = SMTPClient.SendOptions(isSSL = true, username = SETTINGS["SMTP_EMAIL"], passwd = SETTINGS["SMTP_PASSWORD"])
        SMTPClient.send(SETTINGS["SMTP_SERVER"], [email], SETTINGS["SMTP_EMAIL"], IOBuffer(body), opt)
    end

end


@post "/registrar" function(req::Request)

    # Let's do this
    (; name, email) = json(req)

    profile = create_profile(name, email)
    invite = create_invite(profile)

    send(invite, profile)

    return Response(301, Dict("Location" => "/registrar"))    
end


@delete "/registrar/{tid}" function(req::Request, tid::String)

    ticketid = TicketID(hex2bytes(tid))

    ticket_index = findfirst(x -> x.ticketid == ticketid, Mapper.RECRUITER[].tickets)
    ticket = Mapper.RECRUITER[].tickets[ticket_index]

    # A lock needs to be acquired here
    @assert isnothing(ticket.admission) "Only in Invited state registration can be removed"
    
    deleteat!(Mapper.RECRUITER[].tickets, ticket_index)

    roll_index = findfirst(x -> x.ticketid == ticketid, ELECTORAL_ROLL.ledger)
    deleteat!(ELECTORAL_ROLL.ledger, roll_index)

    return Response(301, Dict("Location" => "/registrar"))
end


@put "/registrar/{tid}" function(req::Request, tid::String)

    ticketid = TicketID(hex2bytes(tid))

    profile = get(ELECTORAL_ROLL, ticketid)
    invite = create_invite(profile) # In this context create is of different meaning

    send(invite, profile)

    return Response(301, Dict("Location" => "/registrar"))
end


struct RecordView
    INDEX::Int
    TYPE::String
    TIMESTAMP::String
    ISSUER::String
    TYPE_LOWERCASE::String
end

RecordView(index, type, timestamp, issuer) = RecordView(index, type, timestamp, issuer, lowercase(type))


using PeaceFounder.Model: Transaction, DemeSpec, Member, NonceCommitment, BraidWork, Proposal, Lot

function row_view(record::Transaction, i::Int)

    type = string(typeof(record))
    timestamp = "unimplemented"
    issuer = """<td><span class="fw-normal">unimplemented</span></td>"""

    return RecordView(i, type, timestamp, issuer)
end


function row_view(record::DemeSpec, i::Int)

    type = "DemeSpec"
    timestamp = Dates.format(record.timestamp, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">Guardian</span></td>"""
    
    return RecordView(i, type, timestamp, issuer)
end


function row_view(record::NonceCommitment, i::Int)

    type = "NonceCommitment"
    timestamp = "to be deprecated"
    issuer = """<td><span class="fw-normal">#1.BraidChain</span></td>"""
    
    return RecordView(i, type, timestamp, issuer)
end

function row_view(record::Member, i::Int)

    # MembershipCertificate is mor suitable than MemberPass
    # - More ceremonial and used for display or record-keeping. This is true as it is not directly used.
    # - Includes the member's name, date of issue, possibly the signatures of officials from the organization. Signatures are essential.
    # - Often issued once upon the initiation of membership and may not require renewal. It's more of a permanent record.


    type = "Membership"
    timestamp = Dates.format(record.admission.timestamp, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Registrar</span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "member")
end


function row_view(record::BraidWork, i::Int)

    type = "Braid Receipt"
    timestamp = "unimplemented date"
    uuid = record.producer.uuid

    issuer = """<td style="padding-top:5px; padding-bottom:0px;"><span class="fw-normal">#1.Braider<div style="font-size: 10px;">$uuid</div></span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "braid")
end


function row_view(record::Proposal, i::Int)

    type = "Proposal"
    timestamp = Dates.format(record.open, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Proposer</span></td>"""

    return RecordView(i, type, timestamp, issuer)
end

function row_view(record::Lot, i::Int)

    type = "Lot"
    timestamp = "to be deprecated"
    issuer = """<td><span class="fw-normal">#1.BraidChain</span></td>"""
    
    return RecordView(i, type, timestamp, issuer)

end


@get "/braidchain" function(req::Request)
    
    #table = RecordView[row_view(r, i) for (i, r) in enumerate(Mapper.BRAID_CHAIN[].ledger) if r !(isa Union{Lot, NonceCommitment})]

    table = RecordView[row_view(r, i) for (i, r) in enumerate(Mapper.BRAID_CHAIN[].ledger) if !(r isa Union{Lot, NonceCommitment})]
    
    return render(joinpath(TEMPLATES, "buletinboard.html"), Dict("TABLE"=>table)) |> html
end


@get "/braidchain/{index}/demespec" function(req::Request, index::Int)

    data = Dict()

    data["INDEX"] = index
    
    spec = Mapper.BRAID_CHAIN[].ledger[index]

    data["TITLE"] = spec.title
    data["UUID"] = string(spec.uuid)
    data["GROUP_NAME"] =  get_option_text(joinpath(TEMPLATES, "partials/group_specs.html"), PeaceFounder.Model.lower_groupspec(spec.crypto.group))

    data["HASH_NAME"] = get_option_text(joinpath(TEMPLATES, "partials/hash_specs.html"), string(spec.crypto.hasher))

    data["HASHER"] = string(spec.crypto.hasher)

    data["GENERATOR"] = chunk_string(string(spec.crypto.generator), 8) |> uppercase


    data["DEMESPEC_HASH"] = chunk_string(string(Model.digest(spec, spec.crypto.hasher)), 8) |> uppercase


    data["GUARDIAN"] = chunk_string(string(spec.guardian), 8) |> uppercase

    data["BRAID_CHAIN"] = chunk_string(string(spec.recorder), 8) |> uppercase

    data["BALLOTBOX"] = chunk_string(string(spec.collector), 8) |> uppercase

    data["REGISTRAR"] = chunk_string(string(spec.recruiter), 8) |> uppercase

    data["PROPOSER"] = chunk_string(string(spec.proposer), 8) |> uppercase

    data["BRAIDER"] = chunk_string(string(spec.braider), 8) |> uppercase
    
    return render(joinpath(TEMPLATES, "deme.html"), data) |> html
end

@get "/braidchain/{index}/member" function(req::Request, index::Int)

    data = Dict()
    data["INDEX"] = index

    record = Mapper.BRAID_CHAIN[].ledger[index]

    data["GENERATOR"] = findprev(x -> x isa BraidWork || x isa DemeSpec, Mapper.BRAID_CHAIN[].ledger, index - 1)
    data["TICKETID"] = chunk_string(string(record.admission.ticketid), 8) |> uppercase
    data["IDENTITY"] = chunk_string(string(record.admission.id), 8) |> uppercase
    data["ISSUE_TIMESTAMP"] = Dates.format(record.admission.timestamp, "d u yyyy, HH:MM")
    data["PSEUDONYM"] = chunk_string(string(record.pseudonym), 8) |> uppercase

    return render(joinpath(TEMPLATES, "member.html"), data) |> html
end


struct AliasView
    ALIAS::Int
    PSEUDONYM::String
end

@get "/braidchain/{index}/braid" function(req::Request, index::Int)
    
    data = Dict()

    data["INDEX"] = index

    braid = Mapper.BRAID_CHAIN[].ledger[index]

    data["DEME_TITLE"] = braid.producer.title
    data["DEME_UUID"] = braid.producer.uuid
    data["HASHER"] = string(braid.producer.crypto.hasher)

    data["DEMESPEC_HASH"] = chunk_string(string(Model.digest(braid.producer, braid.producer.crypto.hasher)), 8) |> uppercase


    pseudonyms = sort!([Model.output_members(braid)...])

    data["OUTPUT_GENERATOR"] = chunk_string(string(Model.output_generator(braid)), 8) |> uppercase
    data["TABLE"] = [AliasView(i, chunk_string(string(p), 8) |> uppercase) for (i, p) in enumerate(pseudonyms)]

    data["MEMBER_COUNT"] = length(pseudonyms)


    data["INPUT_GENERATOR"] = findprev(x -> x isa BraidWork || x isa DemeSpec, Mapper.BRAID_CHAIN[].ledger, index - 1)

    new_members = [i for (i, r) in enumerate(Mapper.BRAID_CHAIN[].ledger) if r isa Member && i > data["INPUT_GENERATOR"]]

    data["ANONIMITY_THRESHOLD_GAIN"] = length(new_members)


    new_member_string = join(["#$i" for i in new_members], ", ")
    
    
    if Mapper.BRAID_CHAIN[].ledger[data["INPUT_GENERATOR"]] isa BraidWork
        data["INPUT_PSEUDONYMS"] = "#" * string(data["INPUT_GENERATOR"]) * "..." * (!isempty(new_members) ? ", " * new_member_string : "")
    else
        data["INPUT_PSEUDONYMS"] = new_member_string
    end
    #findprev(x -> x isa Braid || x isa DemeSpec, Mapper.BRAID_CHAIN[].ledger, index)


    return render(joinpath(TEMPLATES, "braid.html"), data) |> html
end

@get "/braidchain/{index}/proposal" function(req::Request, index::Int)
    
    record = Dict()
    record["INDEX"] = index

    proposal = Mapper.BRAID_CHAIN[].ledger[index]

    record["TITLE"] = proposal.summary
    record["UUID"] = proposal.uuid
    record["OPENS"] = Dates.format(proposal.open, "d u yyyy, HH:MM")
    record["CLOSES"] = Dates.format(proposal.closed, "d u yyyy, HH:MM")
    record["ANCHOR"] = proposal.anchor.index
    record["MEMBER_COUNT"] = proposal.anchor.member_count

    # %sha256 and such could be used for denoting hash type

    record["BRAIDCHAIN_ROOT"] = join(["#$(proposal.anchor.index)", chunk_string(string(proposal.anchor.root), 8) |> uppercase], ":")
    record["ELECTORAL_ROLL_ROOT"] = join(["§334", chunk_string(string(proposal.anchor.root), 8) |> uppercase], ":")

    record["DESCRIPTION"] = proposal.description
    record["BALLOT_TYPE"] = "Simple Ballot"
    #record["BALLOT"] = string(proposal.ballot)

    record["BALLOT"] = join(["""<p style="margin-bottom: 0;"> $i </p>""" for i in proposal.ballot.options],"\n")

    return render(joinpath(TEMPLATES, "proposal_record.html"), record) |> html
end



struct VoteView
    CAST::Int
    TIMESTAMP::String
    PSEUDONYM::String
    SEQ::Int
    SELECTION::String
    STATUS::String
end


using PeaceFounder.Model: CastRecord, Proposal, BraidWork, Pseudonym, Selection



function Base.isless(a::Pseudonym, b::Pseudonym)
    
    len_a = length(a.pk)
    len_b = length(b.pk)
    minlen = min(len_a, len_b)

    for i in 1:minlen
        if a.pk[i] != b.pk[i]
            return a.pk[i] < b.pk[i]
        end
    end

    return len_a < len_b
end



function create_view(votes::Vector{CastRecord}, proposal::Proposal, braid::BraidWork)

    # I would use the same thing in the 
    pseudonyms = sort!([Model.output_members(braid)...])
    
    table = VoteView[]


    for (cast, v) in enumerate(votes)

        timestamp = Dates.format(v.timestamp, "d u yyyy, HH:MM")
        
        pindex = findfirst(x -> x == v.vote.approval.pbkey, pseudonyms)
        seq = v.vote.seq

        selection = string(v.vote.selection.option)

        next_vote = findnext(x -> x.vote.approval.pbkey == v.vote.approval.pbkey && x.vote.seq >= v.vote.seq, votes, cast + 1)


        if Model.isconsistent(v.vote.selection, proposal.ballot)

            if isnothing(next_vote)
                status = """<span class="fw-bold text-success">Valid</span>"""
            else
                status = """<span class="fw-bold text-warning">Overriden</span>""" # Overruled (used by higher outhorithy), Overloaded
            end

        else
            status = """<span class="fw-bold text-danger">Malformed</span>"""
        end


        vote_view = VoteView(cast, timestamp, string(pindex), seq, selection, status)

        push!(table, vote_view)
    end

    return table
end


@get "/braidchain/{index}/ballotbox" function(req::Request, index::Int)
    
    data = Dict()

    data["INDEX"] = index

    proposal = Mapper.BRAID_CHAIN[].ledger[index]
    bbox = Mapper.ballotbox(proposal.uuid)
    braid = Mapper.BRAID_CHAIN[].ledger[proposal.anchor.index]

    data["TABLE"] = create_view(bbox.ledger, proposal, braid)

    return render(joinpath(TEMPLATES, "proposal_ballotbox.html"), data) |> html
end

using Printf


function format_percent(fraction)

    number = fraction * 100

    if isinteger(number)
        return (@sprintf("%d", number)) * "%"  # Integer formatting
    else
        return (@sprintf("%.1f", number)) * "%"  # One decimal place formatting
    end
end

@get "/braidchain/{index}/tally" function(req::Request, index::Int)

    data = Dict()    

    data["INDEX"] = index
    
    proposal = Mapper.BRAID_CHAIN[].ledger[index]
    bbox = Mapper.ballotbox(proposal.uuid)

    data["VOTES_COUNT"] = bbox.commit.state.index

    # Assumes that only valid pseudonyms have signed the votes, which is true
    # for a record to be inlcuded into ballotbox ledger.
    tally_bitmask = PeaceFounder.Model.tallyview(bbox.ledger, proposal.ballot)
    
    data["VALID_VOTES_COUNT"] = count(tally_bitmask)


    data["PARTICIPATION"] = format_percent(count(tally_bitmask)/proposal.anchor.member_count)
    
    _tally = tally(proposal.ballot, PeaceFounder.Model.selections(bbox.ledger[tally_bitmask]))

    lines = ""

    for (o, t) in zip(proposal.ballot.options, _tally.data)

        lines *= """<p style="margin-bottom: 0;">$o : $t</p>\n"""

    end

    #data["TALLY"] = string(_tally)
    data["TALLY"] = lines
    

    data["BALLOTBOX_TREE_ROOT"] = chunk_string(string(bbox.commit.state.root), 8) |> uppercase # bytes2hex may be a better here
    
    
    if isnothing(bbox.commit.state.tally)

        data["RELEASES"] = "Scheduled on " * Dates.format(proposal.closed, "d u yyyy, HH:MM")

    else
        data["RELEASES"] = """Released on <span id="under-construction">6 Jan 2024, 23:00</span>"""
        data["ACTION"] = """disabled="disabled" """

    end


    return render(joinpath(TEMPLATES, "proposal_tally.html"), data) |> html
end


@post "/braidchain/{index}/tally" function(req::Request, index::Int)
    
    proposal = Mapper.BRAID_CHAIN[].ledger[index]
    Mapper.tally_votes!(proposal.uuid)

    return Response(301, Dict("Location" => "/braidchain/$index/tally"))
    #return Response(301, Dict("Location" => "/braidchain/$index/tally"))
end



@get "/braidchain/{index}/lot" function(req::Request, index::Int)
    
    data = Dict("INDEX"=>index)    

    return Response(301, Dict("Location" => "/braidchain"))    
end


@get "/braidchain/{index}/noncecommitment" function(req::Request, index::Int)
    
    data = Dict("INDEX"=>index)

    return Response(301, Dict("Location" => "/braidchain"))
end


@get "/braidchain/{index}" function(req::Request, index::Int)

    record = Mapper.BRAID_CHAIN[].ledger[index]

    if record isa DemeSpec
        return Response(301, Dict("Location" => "/braidchain/$index/demespec"))
    elseif record isa Member
        return Response(301, Dict("Location" => "/braidchain/$index/member"))
    elseif record isa Proposal
        return Response(301, Dict("Location" => "/braidchain/$index/proposal"))
    elseif record isa BraidWork
        return Response(301, Dict("Location" => "/braidchain/$index/braid"))
    else record isa Union{Lot, NonceCommitment}
        return  Response(301, Dict("Location" => "/braidchain"))
    end
end


@get "/braidchain/new-braid" function(req::Request)


    spec = Mapper.BRAID_CHAIN[].ledger[1]

    data = Dict()

    data["TITLE"] = spec.title
    data["UUID"] = spec.uuid
    data["GUARDIAN"] = chunk_string(string(spec.guardian), 8) |> uppercase


    return render(joinpath(TEMPLATES, "new-braid.html"), data) |> html
end

@post "/braidchain/new-braid" function(req::Request)

    spec = Mapper.BRAID_CHAIN[].ledger[1]

    input_generator = Mapper.get_generator()
    input_members = Mapper.get_members()

    braidwork = Model.braid(input_generator, input_members, spec, spec, Mapper.BRAIDER[]) 

    Mapper.submit_chain_record!(braidwork)

    return Response(301, Dict("Location" => "/braidchain"))
end



@get "/braidchain/new-proposal" function(req::Request)

    defaults = Dict()

    defaults["TODAY"] = Dates.format(Dates.today(), "dd/mm/yyyy")
    defaults["TOMORROW"] = Dates.format(Dates.today() + Dates.Day(1), "dd/mm/yyyy")
    defaults["CURRENT_ANCHOR"] = findlast(x -> x isa BraidWork, Mapper.BRAID_CHAIN[].ledger)

    return render(joinpath(TEMPLATES, "new-proposal.html"), defaults) |> html
end


using PeaceFounder.Model: generator, root, members, ChainState, BraidChain


function _state(chain::BraidChain, index::Int)

    g = generator(chain, index)
    r = root(chain, index)
    member_count = length(members(chain, index))

    return ChainState(index, r, g, member_count)
end




@post "/braidchain/new-proposal" function(req::Request)

     (; title, description, open_date, open_time, close_date, close_time, ballot_type, ballot, anchor, release_date, release_time) = json(req)

    isempty(open_time) && (open_time="00:00")
    isempty(close_time) && (close_time="00:00")

    isempty(release_date) && (release_date=close_date)
    isempty(release_time) && (release_time=close_time)


    if isempty(anchor)
        anchor_index = findlast(x -> x isa BraidWork, Mapper.BRAID_CHAIN[].ledger)
    else
        if anchor[1] == "#"
            anchor_index = parse(Int, anchor[2:end])
        else
            anchor_index = parse(Int, anchor)
        end
    end

    # I need to retrieve a state of the braidchain
    anchor_state = _state(Mapper.BRAID_CHAIN[], anchor_index)

    open_datetime = DateTime(join([open_date, open_time], " "), "dd/mm/yyyy HH:MM")
    close_datetime = DateTime(join([close_date, close_time], " "), "dd/mm/yyyy HH:MM")
    release_datetime = DateTime(join([release_date, release_time], " "), "dd/mm/yyyy HH:MM")

    parsed_ballot = Ballot(split(ballot, "\n"))

    roles = Mapper.system_roles()

    proposal = Proposal(
        uuid = UUIDs.uuid4(),
        summary = title, # need to rename as title
        description = description,
        ballot = parsed_ballot,
        open = open_datetime,
        closed = close_datetime,
        collector = roles.collector, # should be deprecated
        
        state = anchor_state # anchor, because the state is in the type
    ) |> approve(PROPOSER[])


    Mapper.submit_chain_record!(proposal)

    return Response(301, Dict("Location" => "/braidchain"))
end


module Patch

# Changes which will be upstreeamed. Relaxes types of votes which are accepted

using Setfield
using PeaceFounder.Model: digest, Vote, seal, generator, Signer, Digest, Proposal, Selection, hasher, BallotBox, Vote, pseudonym, isbinding, members, verify
using PeaceFounder.Model: Ballot, isconsistent, CastRecord
import PeaceFounder


function PeaceFounder.Model.validate(ballotbox::BallotBox, vote::Vote)

    @assert isbinding(vote, ballotbox.proposal, ballotbox.crypto) 
    @assert pseudonym(vote) in members(ballotbox)

    @assert verify(vote, generator(ballotbox), ballotbox.crypto)

    return
end

# This is something that will need to be upstreamed

function PeaceFounder.Model.tallyview(votes::Vector{CastRecord}, ballot::Ballot) # maybe valid_votes would be a better name
    
    valid_votes = BitVector(false for i in 1:length(votes))

    for (i, v) in enumerate(votes)

        if isconsistent(v.vote.selection, ballot)
            next_vote = findnext(x -> x.vote.approval.pbkey == v.vote.approval.pbkey && x.vote.seq >= v.vote.seq, votes, i + 1)
            if isnothing(next_vote)
                valid_votes[i] = true
            end
        end
    end

    return valid_votes
end


end


end
