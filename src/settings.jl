import SMTPClient


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
