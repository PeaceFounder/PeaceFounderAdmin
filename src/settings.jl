import SMTPClient


module SETTINGS

SERVER_ROUTE::String = ""

SMTP_EMAIL::String = "" 
SMTP_PASSWORD::String = ""
SMTP_SERVER::String = "" # I did put a placeholder

#INVITE_DEME_ADDRESS = ""
INVITE_SUBJECT::String = "Membership Invite to Deme" # I could use {{DEME}}
INVITE_TEXT::String = """

Dear {{{NAME}}},

To begin your journey with PeaceFounder, simply launch the PeaceFounder client on your device and enter the invite code shown below. The rest of the process will be handled automatically by your device.

{{{INVITE}}}

Once registered, on your device you'll see a registration index, indicating your membership certificate's inclusion in BraidChain ledger. This index confirms your successful registration.

For auditing and legitimacy, please send a document within two weeks listing your registration index and the invite code, signed with your digital identity provider. Note that failure to complete this step will result in membership termination.

Guardian
{{DEME}}\

"""

# can be dynamically generated
# however may benefit for providing a granular handles
@eval function reset()

    global SERVER_ROUTE = $SERVER_ROUTE

    global SMTP_EMAIL = $SMTP_EMAIL
    global SMTP_PASSWORD = $SMTP_PASSWORD
    global SMTP_SERVER = $SMTP_SERVER

    global INVITE_SUBJECT = $INVITE_SUBJECT
    global INVITE_TEXT = $INVITE_TEXT
    
    return
end


hassmtp() = !isempty(SMTP_EMAIL) && !isempty(SMTP_SERVER) && !isempty(SMTP_PASSWORD)

end



@get "/settings" function(req::Request)

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

    return 
end


@post "/settings/invite" function(req::Request)

    (; address, time, subject, text) = json(req)

    SETTINGS.SERVER_ROUTE = address
    SETTINGS.INVITE_SUBJECT = subject
    SETTINGS.INVITE_TEXT = text

    return
end
