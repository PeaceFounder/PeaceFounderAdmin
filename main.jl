using Oxygen
using HTTP: Request, Response
using Mustache
using Infiltrator
using PeaceFounder

using UUIDs

using PeaceFounder.Model: CryptoSpec, pseudonym, TicketID, Member, Proposal, Ballot, Selection, generator, state, id, vote, seed, tally, approve, istallied, DemeSpec, hasher, HMAC, auth, token, isbinding, Generator, generate, Signer


import SMTPClient


# 
SERVER_PORT = Ref(4584)


TEMPLATES = joinpath(@__DIR__, "templates")

dynamicfiles(joinpath(@__DIR__, "public"), "/")
#staticfiles(joinpath(@__DIR__, "public"), "/")
#staticfiles(joinpath(@__DIR__, "mockup"), "/")

# This should be part of the mapper
const PROPOSER = Ref{Signer}()

const DEMESPEC_CANDIDATE = Ref{DemeSpec}()


const SETTINGS = Dict{String, String}()

const SETTINGS_DEFAULT = Dict{String, String}()


#
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

Guardian\
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
    
    guardian_pbkey = chunk_string(string(guardian), 8) |> uppercase

    # For this one I would need to do key maangement manually
    roles = raw"<b>BraidChain</b>, <s>BallotBox</s>, <b>Registrar</b>, <s>Proposer</s>, <s>Braider</s>"
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



# For testing purposes
function init_state()

    title = "Some Community"
    hash = "sha256"
    group = "EC: P_192"

    crypto = CryptoSpec(hash, group)

    guardian = generate(Signer, crypto)
    proposer = generate(Signer, crypto)
    
    Mapper.initialize!(crypto)

    roles = Mapper.system_roles()
    
    spec = DemeSpec(;
                    uuid = UUIDs.uuid4(),
                    title = title,
                    crypto = crypto,
                    guardian = id(guardian),
                    recorder = roles.recorder,
                    recruiter = roles.recruiter,
                    braider = roles.braider,
                    proposer = id(proposer),
                    collector = roles.collector
                    ) |> approve(guardian)
    

    Mapper.capture!(spec)

    SETTINGS["SMTP_EMAIL"] = "demeregistrar@inbox.lv"
    SETTINGS["SMTP_SERVER"] = "smtps://mail.inbox.lv:465"
    #SETTINGS["SMTP_PASSWORD"] = ENV["RECRUIT_EMAIL_PASSWORD"] 
    SETTINGS["SMTP_PASSWORD"] = ENV["REGISTRAR_PASSWORD"] 

    return    
end

init_state()


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

    SETTINGS["INVITE_ADDRESS"] = address
    SETTINGS["INVITE_SUBJECT"] = subject
    SETTINGS["INVITE_TEXT"] = text

    return
end



using Dates


abstract type MemberState end

struct Invited <: MemberState 
    expired::Bool
end 

struct Admitted <: MemberState 
    expired::Bool
end

struct Registered <: MemberState
    index::Int
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

    registration_index = get_registration_index(PeaceFounder.Mapper.BRAID_CHAIN[].ledger, ticketid)

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
# sort by index

const ELECTORAL_ROLL = ElectoralRoll()


update!(profile::MemberProfile) = profile.state = get_registration_status(profile.ticketid)

function update!(roll::ElectoralRoll)

    for profile in roll.ledger
        update!(profile) 
    end

    return
end


# This is registered in a roll
function create_profile(name::String, email::String)

    if email != "DEBUG" 
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




@get "/registrar" function(req::Request)
    
    return render(joinpath(TEMPLATES, "registrar.html")) |> html
end


@post "/registrar" function(req::Request)

    # Let's do this
    (; name, email) = json(req)

    profile = create_profile(name, email)
    invite = create_invite(profile)

    invite_code = String(PeaceFounder.Parser.marshal(invite))

    invite_rendered = Mustache.render(SETTINGS["INVITE_TEXT"], Dict("INVITE"=>invite_code, "NAME"=>name))

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
    else
        opt = SMTPClient.SendOptions(isSSL = true, username = SETTINGS["SMTP_EMAIL"], passwd = SETTINGS["SMTP_PASSWORD"])
        SMTPClient.send(SETTINGS["SMTP_SERVER"], [email], SETTINGS["SMTP_EMAIL"], IOBuffer(body), opt)
    end

    return Response(301, Dict("Location" => "/registrar"))    
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
    TIMESTAMP = string(created)

    if state isa Invited

        REGISTRATION = "Invited"
        STATUS = "OK"

    elseif state isa Admitted

        REGISTRATION = "Admitted"
        STATUS = "Pending"

    elseif state isa Registered
        
        REGISTRATION = string(state.index)

        if state.verified
            STATUS = "Verified"
        else
            STATUS = "Trial"
        end
        
    end

    return MemberProfileView(TICKETID, NAME, EMAIL, TIMESTAMP, REGISTRATION, STATUS)
end








@get "/buletinboard" function(req::Request)
    
    return render(joinpath(TEMPLATES, "buletinboard.html")) |> html
end




import HTTP

try
    global service = HTTP.serve!(PeaceFounder.Service.ROUTER, "0.0.0.0", SERVER_PORT[])
    Oxygen.serve(port=3221)
finally 
    close(service)
end




