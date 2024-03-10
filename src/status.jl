# Here I could couple in metrics 

@get "/status" function(req::Request)

    #demespec = Mapper.BRAID_CHAIN[][1] # keep it simple

    demespec = Mapper.get_demespec()

    #DATA = Dict{String, String}()

    #DATA["UUID"] = string(demespec.uuid)
    #DATA["TITLE"] = demespec.title

    #return render(joinpath(TEMPLATES, "status.html"), DATA) |> html
    render_template("status.html") <| [
        :UUID => string(demespec.uuid),
        :TITLE => demespec.title
    ]

end


