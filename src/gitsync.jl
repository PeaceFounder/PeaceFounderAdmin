using Base: match

include("Utils/LocalSync.jl")
import .LocalSync

include("Utils/GitSync.jl")
import .GitSync

include("Utils/BuletinBoardFacade.jl")
import .BuletinBoardFacade


function init_ssh_keypair()
    
    key_path = joinpath(dirname(SETTINGS.PATH), "secret", "ssh", "key")
    GitSync.generate_ssh_keypair(key_path)

    return
end

function reset_ssh_keypair()

    if isempty(SETTINGS.PATH) 
        @warn "Data directory is unset"
        return
    end

    key_path = joinpath(dirname(SETTINGS.PATH), "secret", "ssh", "key")

    rm(key_path, force=true)
    rm("$key_path.pub", force=true)

    init_ssh_keypair()

    return
end


function get_ssh_pubkey()
    
    key_path = joinpath(dirname(SETTINGS.PATH), "secret", "ssh", "key")

    if isfile(key_path)
        return GitSync.get_ssh_pubkey(key_path)
    else
        return ""
    end
end

function repo_path(remote::String)
    pattern = r"(?<=:)([^.]+)"
    m = match(pattern, remote)
    return m.match
end


function init_git_repo()

    if isempty(SETTINGS.PATH) 
        @warn "Data directory is unset"
        return
    end

    repo = joinpath(dirname(SETTINGS.PATH), "cache", "repo")
    known_hosts = joinpath(dirname(SETTINGS.PATH), "cache", "known_hosts")
    key = joinpath(dirname(SETTINGS.PATH), "secret", "ssh", "key")
    
    mkpath(repo)

    # If git remote changes the repo could be reset
    #GitSync.git_init(repo, SETTINGS.GIT_REMOTE, key; known_hosts)
    GitSync.git_init(repo, SETTINGS.GIT_REMOTE)

    host = GitSync.extract_host(SETTINGS.GIT_REMOTE)
    GitSync.hosts_init(host; known_hosts)

    GitSync.git_sync(repo, key; commit = "init", known_hosts, stage="README.md .github") do

        BuletinBoardFacade.init_readme(repo, repo_path(SETTINGS.GIT_REMOTE))
        BuletinBoardFacade.init_audit_workflow(repo)

    end

    return
end

function reset_git_repo()

    if isempty(SETTINGS.PATH) 
        @warn "Data directory is unset"
        return
    end

    repo = joinpath(dirname(SETTINGS.PATH), "cache", "repo")
    rm(joinpath(repo, ".git"), recursive=true, force=true)
    init_git_repo()

    return
end

function git_push(; commit = "server event", presync = false)

    if isempty(SETTINGS.PATH) 
        @warn "Data directory is unset"
        return
    end

    repo = joinpath(dirname(SETTINGS.PATH), "cache", "repo")
    known_hosts = joinpath(dirname(SETTINGS.PATH), "cache", "known_hosts")
    key = joinpath(dirname(SETTINGS.PATH), "secret", "ssh", "key")

    braidchain = joinpath(dirname(SETTINGS.PATH), "public", "braidchain")
    bboxes = joinpath(dirname(SETTINGS.PATH), "public", "ballotboxes")
    
    # If one reintilises the repo it is somewhat desirable to also sync beforehand
    # as that would reduce disk usage with hardlinks
    if presync
        LocalSync.sync(braidchain, joinpath(repo, "braidchain"))
        LocalSync.sync(bboxes, joinpath(repo, "ballotboxes"))
    end

    GitSync.git_sync(repo, key; commit, known_hosts, stage="braidchain ballotboxes") do

        LocalSync.sync(braidchain, joinpath(repo, "braidchain"))
        LocalSync.sync(bboxes, joinpath(repo, "ballotboxes"))
        
    end

    return
end
