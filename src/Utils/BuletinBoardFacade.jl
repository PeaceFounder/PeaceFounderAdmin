module BuletinBoardFacade

using Mustache


function init_readme(dest::AbstractString, repo::AbstractString)

    readme_path = joinpath(dest, "README.md")

    if isfile(readme_path)
        @info "README already initialized. Remove it manuallly on remote to reinitialize it."
        return
    end

    tmpl = Mustache.load(joinpath(@__DIR__, "assets", "README.md"))
    _render = Mustache.render(tmpl, GITHUB_REPO = repo)
    write(readme_path, _render)

    return
end


function init_audit_workflow(dest::AbstractString)

    workflow_path = joinpath(dest, ".github", "workflows", "audit_workflow.yml")

    if isfile(workflow_path)
        @info "GitHub workflow already initialized. Remove it manually on remote to reinitialize it."
        return
    end
    
    mkpath(dirname(workflow_path))
    cp(joinpath(@__DIR__, "assets", "audit_workflow.yml"), workflow_path, force = true)
    
    return 
end


end
