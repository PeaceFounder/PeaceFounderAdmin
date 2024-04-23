using PeaceFounderAdmin

using Dates: Dates, UTC
using UUIDs

using PeaceFounder
using PeaceFounder: Client
using PeaceFounder.Server: Mapper, Service
using PeaceFounder.Core.Model: CryptoSpec, generate, Signer, DemeSpec, id, approve, Ballot, Proposal, Selection, braid, index

ENV["USER_DATA"] = joinpath(tempdir(), "peacefounderadmin")
rm(ENV["USER_DATA"], force=true, recursive=true)
mkdir(ENV["USER_DATA"])

include("../examples/integration/setup.jl")

function cast_vote!(client, uuid, proposal, selection; force=true, seq=nothing)

    Client.cast_vote!(client, uuid, proposal, selection; force, seq)

    account = Client.select(client, uuid)
    (; guard) = Client.get_proposal_instance(account, proposal)

    code = Client.tracking_code(guard, account.deme)
    _index = index(guard)
    println("TRACKING_CODE $_index: $code")
    
    return
end

# For testing purposes
function init_test_state()

    title = "Some Community"
    hash = "sha256"
    group = "EC: P_192"

    crypto = CryptoSpec(hash, group)

    guardian = generate(Signer, crypto)

    authorized_roles = Mapper.setup(crypto.group, crypto.generator) do pbkeys

        return DemeSpec(;
                        uuid = Base.UUID(rand(UInt128)),
                        title = "A local democratic communituy",
                        email = "guardian@peacefounder.org",
                        crypto = crypto,
                        recorder = pbkeys[1],
                        registrar = pbkeys[2],
                        braider = pbkeys[3],
                        proposer = pbkeys[4],
                        collector = pbkeys[5]
                        ) |> approve(guardian) 

    end

    proposer = Mapper.PROPOSER[]
    demespec = Mapper.get_demespec() #Mapper.BRAID_CHAIN[].spec

    token_key = Mapper.token_key()
    token_length = Mapper.token_nlen()

    println("TOKEN_LENGTH: $token_length")
    println("TOKEN_KEY: $(bytes2hex(token_key))")


    PeaceFounderAdmin.SETTINGS.SMTP_EMAIL = "demeregistrar@inbox.lv"
    PeaceFounderAdmin.SETTINGS.SMTP_SERVER = "smtps://mail.inbox.lv:465"
    PeaceFounderAdmin.SETTINGS.SMTP_PASSWORD = ENV["REGISTRAR_PASSWORD"] 


    # For debugging the Electoral Roll view
    # create_profile("Peter Parker", "DEBUG").state = Invited(false)
    # create_profile("Harry Potter", "DEBUG").state = Invited(true)
    # create_profile("Sherlock Holmes", "DEBUG").state = Admitted(false)
    # create_profile("Frodo Baggins", "DEBUG").state = Admitted(true)
    # create_profile("Walter White", "DEBUG").state = Registered(3, false)
    # create_profile("Indiana Jones", "DEBUG").state = Registered(3, true)
    # create_profile("Luke Skywalker", "DEBUG").state = Terminated(4, 6)

    
    Mapper.set_route(PeaceFounderAdmin.SETTINGS.SERVER_ROUTE)
    PeaceFounderAdmin.SETUP_DONE = true


    profile = PeaceFounderAdmin.create_profile("Alice", "DEBUG")
    invite = Mapper.enlist_ticket(profile.ticketid)
    lisbeth = Client.DemeClient()
    Client.enroll!(lisbeth, invite, key = 4)

    profile = PeaceFounderAdmin.create_profile("Bob", "DEBUG")
    invite = Mapper.enlist_ticket(profile.ticketid)
    dorian = Client.DemeClient()
    Client.enroll!(dorian, invite, key = 3)
    
    profile = PeaceFounderAdmin.create_profile("Eve", "DEBUG") #Holly Golightly
    invite = Mapper.enlist_ticket(profile.ticketid)
    winston = Client.DemeClient() 
    Client.enroll!(winston, invite, key = 5) # need to look into key attribute a
    # Also randomness in ShuffleProofs seems to be fixated during compilation time and thus need to be improved.

    # Self-Braiding

    input_generator = Mapper.get_generator()
    input_members = Mapper.get_members()

    braidreceipt = braid(input_generator, input_members, demespec.crypto, demespec, Mapper.BRAIDER[]) 

    Mapper.submit_chain_record!(braidreceipt)

    # Adding of a proposal

    commit = Mapper.BRAID_CHAIN[].commit

    proposal = Proposal(
        uuid = Base.UUID("49e9ebce-fb9e-5b83-1534-75cff3ee423a"),
        summary = "Should the city ban all personal vehicle usage and invest in alternative forms of transportation such as public transit, biking and walking infrastructure?",
        description = "",
        ballot = Ballot(["Yes", "No"]),
        open = Dates.now(UTC),
        closed = Dates.now(UTC) + Dates.Second(600),
        collector = id(Mapper.COLLECTOR[]), # should be deprecated

        state = commit.state
    ) |> approve(proposer)


    index = Mapper.submit_chain_record!(proposal).proof.index

    #23424:sha256:
    # Adding few votes

    sleep(1)

    Client.update_deme!(lisbeth, demespec.uuid)
    Client.update_deme!(dorian, demespec.uuid)
    Client.update_deme!(winston, demespec.uuid)
    
    cast_vote!(lisbeth, demespec.uuid, index, Selection(2), seq = 1)
    cast_vote!(lisbeth, demespec.uuid, index, Selection(1), seq = 1)
    cast_vote!(winston, demespec.uuid, index, Selection(2))
    cast_vote!(dorian, demespec.uuid, index, Selection(1))
    cast_vote!(dorian, demespec.uuid, index, Selection(3), force=true)
    cast_vote!(winston, demespec.uuid, index, Selection(1))

    return
end


function ReviseHandler(handle)
    req -> begin
        Revise.revise()
        invokelatest(handle, req)
    end
end



PeaceFounderAdmin.serve(server_middleware=[ReviseHandler], admin_middleware=[ReviseHandler]) do

    if isempty(readdir(ENV["USER_DATA"]))
        init_test_state()
    end

end

