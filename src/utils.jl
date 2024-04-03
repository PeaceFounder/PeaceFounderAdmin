using OpenSSL_jll: openssl 

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


function openssl_encrypt(data::Vector{UInt8}, password::String)

    # Prepare the OpenSSL encryption command
    encrypt_cmd = `$(openssl()) enc -aes-256-cbc -pbkdf2 -salt -pass pass:$password`
    
    # Create a pipe to write data to and read from the OpenSSL process
    process = open(encrypt_cmd, "r+")
    
    # Write the data to the process's standard input
    write(process, data)
    close(process.in)  # Important to close the input stream to signal end of data
    
    # Read the encrypted data from the process's standard output
    encrypted_data = read(process, String)
    close(process)  # Close the process
    
    return encrypted_data
end

# Function to decrypt data
function openssl_decrypt(encrypted_data::String, password::String)
    # Prepare the OpenSSL decryption command
    decrypt_cmd = `$(openssl()) enc -aes-256-cbc -pbkdf2 -d -salt -pass pass:$password`
    
    # Create a pipe to write data to and read from the OpenSSL process
    process = open(decrypt_cmd, "r+")
    
    # Write the encrypted data to the process's standard input
    write(process, encrypted_data)
    close(process.in)  # Close the input stream to signal end of data
    
    # Read the decrypted data from the process's standard output
    decrypted_data = read(process, String)
    close(process)  # Close the process
    
    return Vector{UInt8}(decrypted_data)
end
