# Here I could couple in metrics 

@get "/status" function(req::Request)

    demespec = Mapper.BRAID_CHAIN[][1] # keep it simple

    DATA = Dict{String, String}()

    DATA["UUID"] = string(demespec.uuid)
    DATA["TITLE"] = demespec.title

    return render(joinpath(TEMPLATES, "status.html"), DATA) |> html
end


