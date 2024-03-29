using PeaceFounder.Core.Model: issuer

using Oxygen: html, json
using Gumbo
using Cascadia

global SETUP_DONE::Bool = false # Consider puttin within settings

function create_deme((; title, email, group, hash, password))

    @warn "Guardian private key encryption unimplemented and won't be stored"

    crypto = CryptoSpec(hash, group)
    guardian = generate(Signer, crypto)

    authorized_roles = Mapper.setup(crypto.group, crypto.generator) do pbkeys

        # A BRAID_CHAIN can be populated with records here

        return DemeSpec(;
                        uuid = Base.UUID(rand(UInt128)),
                        title = title,
                        email = email,
                        crypto = crypto,
                        recorder = pbkeys[1],
                        registrar = pbkeys[2],
                        braider = pbkeys[3],
                        proposer = pbkeys[4],
                        collector = pbkeys[5]
                        ) |> approve(guardian) 

    end

    return
end


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


@get "/setup" function(req::Request)

    tmp = Mustache.load(joinpath(TEMPLATES, "wizard-step-1.html"))

    return Mustache.render(tmp) |> html
end


@get "/configurator" function(req::Request)

    return render(joinpath(TEMPLATES, "wizard-step-2a.html")) |> html
end


@post "/configurator" function(req::Request)
    

    (; title, email, group, hash, password) = json(req)

    @warn "Guardian private key encryption unimplemented and won't be stored"

    # group and hash needs to come in here
    crypto = CryptoSpec(hash, group)
    guardian = generate(Signer, crypto)

    authorized_roles = Mapper.setup(crypto.group, crypto.generator) do pbkeys

        # A BRAID_CHAIN can be populated with records here

        return DemeSpec(;
                        uuid = Base.UUID(rand(UInt128)),
                        title = title,
                        email = email,
                        crypto = crypto,
                        recorder = pbkeys[1],
                        registrar = pbkeys[2],
                        braider = pbkeys[3],
                        proposer = pbkeys[4],
                        collector = pbkeys[5]
                        ) |> approve(guardian) 

    end


    Mapper.set_route(SETTINGS.SERVER_ROUTE)

    return
end


# TODO: update with using authorized_roles function
@get "/setup-summary" function(req::Request)

    spec = Mapper.get_demespec()
    (; uuid, title, crypto, recorder, registrar, braider, proposer, collector) = spec

    group_name = get_option_text(joinpath(TEMPLATES, "partials/group_specs.html"), Model.lower_groupspec(crypto.group))
    hash_name = get_option_text(joinpath(TEMPLATES, "partials/hash_specs.html"), string(crypto.hasher))

    #roles = raw"<b>BraidChain</b>, <s>BallotBox</s>, <b>Registrar</b>, <s>Proposer</s>, <s>Braider</s>"
    # TODO: use authorized_roles
    roles = raw"<b>BraidChain</b>, <b>BallotBox</b>, <b>Registrar</b>, <b>Proposer</b>, <b>Braider</b>"
    commit = "#1"

    return render_template("wizard-step-3.html") <| [
        :TITLE => title,
        :UUID => uuid,
        :GROUP_NAME => group_name,
        :HASH_NAME => hash_name,
        :GUARDIAN => chunk_string(string(issuer(spec)), 8) |> uppercase,
        :ROLES => roles,
        :COMMIT => commit,
        :ISSUE_DATE => format_date_ordinal(spec.seal.timestamp)
    ]
end 


@post "/setup-summary" function(req::Request)

    # Note that commit is already done with the setup phase

    global SETUP_DONE = true

    return Response(302, Dict("Location" => "/")) # One wants to be sure that it indeed works
end
