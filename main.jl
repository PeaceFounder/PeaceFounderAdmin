using Oxygen
using HTTP: Request, Response
using Mustache
using Infiltrator
using PeaceFounder

using UUIDs

using PeaceFounder.Model: CryptoSpec, pseudonym, TicketID, Member, Proposal, Ballot, Selection, generator, state, id, vote, seed, tally, approve, istallied, DemeSpec, hasher, HMAC, auth, token, isbinding, Generator, generate, Signer


TEMPLATES = joinpath(@__DIR__, "templates")

staticfiles(joinpath(@__DIR__, "public"), "/")
#staticfiles(joinpath(@__DIR__, "mockup"), "/")

# This should be part of the mapper
const PROPOSER = Ref{Signer}()

const DEMESPEC_CANDIDATE = Ref{DemeSpec}()


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

hassmtp() = false


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

    return render(joinpath(TEMPLATES, "settings.html")) |> html
end

@get "/status" function(req::Request)

    return render(joinpath(TEMPLATES, "status.html")) |> html
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

    return    
end


init_state()



Oxygen.serve(port=3221)
