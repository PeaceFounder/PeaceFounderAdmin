function chunk_string(s::String, chunk_size::Int)
    return join([s[i:min(i+chunk_size-1, end)] for i in 1:chunk_size:length(s)], " ")
end

function render(fname, args...; kwargs...) # I could have a render template
    
    dir = pwd()
    
    try
        cd(dirname(fname))

        tmpl = Mustache.load(fname)
        return Mustache.render(tmpl, args...; kwargs...)
        
    finally
        cd(dir)
    end
end

#render(fname) = arg_vec -> render(fname, Dict(arg_vec))


render_template(fname, args...; kwargs...) = render(joinpath(TEMPLATES, fname), args...; kwargs...) |> html

render_template(fname) = arg_vec -> render_template(fname, Dict([string(key) => val for (key, val) in arg_vec]))


(f <| x) = f(x) 


function ordinal_suffix(day)
    if day in [11, 12, 13]
        return "th"
    elseif day % 10 == 1
        return "st"
    elseif day % 10 == 2
        return "nd"
    elseif day % 10 == 3
        return "rd"
    else
        return "th"
    end
end

# Function to format the date
function format_date_ordinal(date)
    # Extract components of the date
    year = Dates.year(date)
    month = Dates.format(date, "u")
    day = Dates.day(date)
    hour = Dates.hour(date)
    minute = Dates.minute(date)
    
    # Combine components with the ordinal suffix
    formatted_date = string(month, " ", day, ordinal_suffix(day), " ", year, " at ", lpad(hour, 2, '0'), ":", lpad(minute, 2, '0'))
    
    return formatted_date
end
