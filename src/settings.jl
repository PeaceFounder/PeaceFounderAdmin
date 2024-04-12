import SMTPClient


module SETTINGS

using TOML

PATH::String = ""

SMTP_EMAIL::String = "" 
SMTP_PASSWORD::String = ""
SMTP_SERVER::String = "" 

SERVER_ROUTE::String = ""
INVITE_SUBJECT::String = "Membership Invite to Deme" # We could use {{DEME}}
INVITE_TEXT::String = """

Dear {{{NAME}}},

To begin your journey with PeaceFounder, simply launch the PeaceFounder client on your device and enter the invite code shown below. The rest of the process will be handled automatically by your device.

{{{INVITE}}}

Once registered, on your device you'll see a registration index, indicating your membership certificate's inclusion in BraidChain ledger. This index confirms your successful registration.

For auditing and legitimacy, please send a document within two weeks listing your registration index and the invite code, signed with your digital identity provider. Note that failure to complete this step will result in membership termination.

Guardian
{{DEME}}\

"""

GIT_REMOTE::String = ""


# Variables which are set dynamically

SSH_PUBLIC_KEY::String = ""



# can be dynamically generated
# however may benefit for providing a granular handles
@eval function reset()

    global PATH = $PATH

    global SMTP_EMAIL = $SMTP_EMAIL
    global SMTP_PASSWORD = $SMTP_PASSWORD
    global SMTP_SERVER = $SMTP_SERVER

    global SERVER_ROUTE = $SERVER_ROUTE
    global INVITE_SUBJECT = $INVITE_SUBJECT
    global INVITE_TEXT = $INVITE_TEXT
    
    global GIT_REMOTE = $GIT_REMOTE

    return
end


hassmtp() = !isempty(SMTP_EMAIL) && !isempty(SMTP_SERVER) && !isempty(SMTP_PASSWORD)


function load()

    settings_dict = TOML.parsefile(PATH)

    # TODO: use subcategories with TOML and thus lowecase fields

    # smtp
    haskey(settings_dict, "SMTP_EMAIL") && (global SMTP_EMAIL = settings_dict["SMTP_EMAIL"])
    haskey(settings_dict, "SMTP_SERVER") && (global SMTP_SERVER = settings_dict["SMTP_SERVER"])
    haskey(settings_dict, "SMTP_PASSWORD") && (global SMTP_PASSWORD = settings_dict["SMTP_PASSWORD"])

    # invite
    haskey(settings_dict, "SERVER_ROUTE") && (global SERVER_ROUTE = settings_dict["SERVER_ROUTE"])
    haskey(settings_dict, "INVITE_SUBJECT") && (global INVITE_SUBJECT = settings_dict["INVITE_SUBJECT"])
    haskey(settings_dict, "INVITE_TEXT") && (global INVITE_TEXT = settings_dict["INVITE_TEXT"])
    
    haskey(settings_dict, "GIT_REMOTE") && (global GIT_REMOTE = settings_dict["GIT_REMOTE"])

    return
end


function store()

    isempty(PATH) && return

    settings_dict = Dict{String, Any}()

    settings_dict["SMTP_EMAIL"] = SMTP_EMAIL
    settings_dict["SMTP_SERVER"] = SMTP_SERVER
    settings_dict["SMTP_PASSWORD"] = SMTP_PASSWORD

    settings_dict["SERVER_ROUTE"] = SERVER_ROUTE
    settings_dict["INVITE_SUBJECT"] = INVITE_SUBJECT
    settings_dict["INVITE_TEXT"] = INVITE_TEXT

    settings_dict["GIT_REMOTE"] = GIT_REMOTE

    open(PATH, "w") do io
           TOML.print(io, settings_dict)
    end

    return
end


end

#const SETTINGS = __SETTINGS.HANDLER

@get "/settings" function(req::Request)

    SETTINGS.SSH_PUBLIC_KEY = get_ssh_pubkey()

    return render(joinpath(TEMPLATES, "settings.html"), SETTINGS) |> html
end


@post "/settings/smtp-test" function(req::Request)
    
    (; email) = json(req)


    body = """
    From: $(SETTINGS.SMTP_EMAIL)
    To: $email
    Subject: This is a SMTP Test

    Hello World!!!

    Deme Server
    """

    opt = SMTPClient.SendOptions(isSSL = true, username = SETTINGS.SMTP_EMAIL, passwd = SETTINGS.SMTP_PASSWORD)
    SMTPClient.send(SETTINGS.SMTP_SERVER, [email], SETTINGS.SMTP_EMAIL, IOBuffer(body), opt)
    
    return Response(302, Dict("Location" => "/settings")) # I could do an error in similar way
end


@post "/settings/smtp" function(req::Request)

    (; email, password, server) = json(req)

    SETTINGS.SMTP_EMAIL = email
    SETTINGS.SMTP_PASSWORD = password # One can spend quite a time to get this working
    SETTINGS.SMTP_SERVER = server

    SETTINGS.store()

    return 
end


@post "/settings/invite" function(req::Request)

    (; address, time, subject, text) = json(req)

    SETTINGS.SERVER_ROUTE = address
    SETTINGS.INVITE_SUBJECT = subject
    SETTINGS.INVITE_TEXT = text

    SETTINGS.store()

    return
end


@post "/settings/git-push" function(req::Request)

    @info "GIT PUSH"

    try 
        git_push()
        return Response(302, Dict("Location" => "/settings"))
    catch error
        @error "ERROR: " exception=(error, catch_backtrace())
        return Response(500, "Git push had been unsucesful. Check accuracy of the remote and check if the pulbic key is correctly deployed to the remmote.")        
    end
end


@post "/settings/git-reset-pbkey" function(req::Request)

    @info "GIT RESET PUBLICKEY"
    
    reset_ssh_keypair()
    return Response(302, Dict("Location" => "/settings"))
end


# With update the repo should only be updated if the name is changed
# Wheras with force it needs to be always updated. Need to work on this
@post "/settings/git-remote" function(req::Request)

    (; remote, force) = json(req)

    @info "Attempting to update git remote to $remote"

    if force == "false" && SETTINGS.GIT_REMOTE == remote
        @info "Skipping update. Nothing to do."
        return
    elseif force == "true"
        @info "Reseting existing remote $remote with force"
    else
        error("Invalid value for force: $force")
    end

    oldremote = SETTINGS.GIT_REMOTE
    try 
        SETTINGS.GIT_REMOTE = remote
        reset_git_repo()
        SETTINGS.store()
    catch err
        SETTINGS.GIT_REMOTE = oldremote
        rethrow(err)
    end

    return
end



