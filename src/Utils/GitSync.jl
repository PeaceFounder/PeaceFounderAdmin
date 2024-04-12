module GitSync

using OpenSSH_jll: ssh, ssh_keygen, ssh_keyscan
using Git: git

function generate_ssh_keypair(key::String)
    
    ssh_dir = dirname(key)

    if isdir(ssh_dir)
        chmod(ssh_dir, 0o700)
    else
        mkdir(ssh_dir, mode=0o700)
    end

    run(`$(ssh_keygen()) -q -t ed25519 -f $key -N ""`)
    return
end

get_ssh_pubkey(key::String) = String(read("$key.pub"))

function hosts_init(host::AbstractString; known_hosts::String = joinpath(homedir(), ".ssh", "known_hosts"))

    keyscan_output = read(`$(ssh_keyscan()) -T 10 $host`, String)
    key_list = split(keyscan_output, "\n")[1:end-1]
    
    known_hosts_list = isfile(known_hosts) ? split(String(read(known_hosts)), "\n") : []
    
    open(known_hosts, "a") do file
        for key in key_list
            if !(key in known_hosts_list)
                write(file, '\n')
                write(file, key)
            else
                println("$key already in known hosts")
            end
        end
    end

    return
end

function extract_host(origin::String)

    regex = r"@([^:]+):"
    match_data = match(regex, origin)
    host = only(match_data.captures)
    
    return host
end

function git_init(dir::String, origin::String)

    git_cmd = git()

    cd(dir) do
        run(`$git_cmd init`)
        run(`$git_cmd remote add origin $origin`)
        run(`$git_cmd branch -M main`)
        run(`$git_cmd config --global http.lowSpeedLimit 0`)
    end 

    return
end

function git_sync(update::Function, dir::String, key::String; commit = "server event", known_hosts::String = joinpath(homedir(), ".ssh", "known_hosts"), stage = ".")

    git_cmd = git()
    ssh_exec = only(ssh().exec)

    withenv("GIT_SSH_COMMAND" => "$ssh_exec -i $key -o IdentitiesOnly=yes -o UserKnownHostsFile=$known_hosts") do
        cd(dir) do
            run(`$git_cmd init`)
            try 
                #run(`$git_cmd pull origin main`)
                run(`$git_cmd fetch --depth 1`)
                run(`$git reset --hard origin/main`)
            catch
                @info "Git fetch failed. Assuming unitialized remote."
            end
        end
    end

    update()

    withenv("GIT_SSH_COMMAND" => "$ssh_exec -i $key -o IdentitiesOnly=yes -o UserKnownHostsFile=$known_hosts") do
        cd(dir) do
            
            stage_args = split(stage, " ")
            run(`$git_cmd add $stage_args`)

            try
                run(`$git_cmd commit -m $commit`)
            catch
                @info "Nothing to commit. Already up to date."
            end
            run(`$git_cmd push origin main`)
        end
    end

    return
end

end
