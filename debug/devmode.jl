using PeaceFounderAdmin

using Dates
using UUIDs

using PeaceFounder
using PeaceFounder: Client
using PeaceFounder.Server: Mapper, Service
using PeaceFounder.Core.Model: CryptoSpec, generate, Signer, DemeSpec, id, approve, Ballot, Proposal, Selection, braid



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


    profile = PeaceFounderAdmin.create_profile("Lisbeth Salander", "DEBUG")
    invite = Mapper.enlist_ticket(profile.ticketid)
    lisbeth = Client.DemeClient()
    Client.enroll!(lisbeth, invite, key = 4)

    profile = PeaceFounderAdmin.create_profile("Dorian Gray", "DEBUG")
    invite = Mapper.enlist_ticket(profile.ticketid)
    dorian = Client.DemeClient()
    Client.enroll!(dorian, invite, key = 3)
    
    profile = PeaceFounderAdmin.create_profile("Winston Smith", "DEBUG") #Holly Golightly
    invite = Mapper.enlist_ticket(profile.ticketid)
    winston = Client.DemeClient() 
    Client.enroll!(winston, invite, key = 5) # need to look into key attribute a
    # Also randomness in ShuffleProofs seems to be fixated during compilation time and thus need to be improved.

    # Self-Braiding

    input_generator = Mapper.get_generator()
    input_members = Mapper.get_members()

    braidreceipt = braid(input_generator, input_members, demespec, demespec, Mapper.BRAIDER[]) 

    Mapper.submit_chain_record!(braidreceipt)

    # Adding of a proposal

    commit = Mapper.BRAID_CHAIN[].commit

    proposal = Proposal(
        uuid = UUIDs.uuid4(),
        summary = "Should the city ban all personal vehicle usage and invest in alternative forms of transportation such as public transit, biking and walking infrastructure?",
        description = "",
        ballot = Ballot(["Yes", "No"]),
        open = Dates.now(),
        closed = Dates.now() + Dates.Second(600),
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
    
    Client.cast_vote!(lisbeth, demespec.uuid, index, Selection(2))
    Client.cast_vote!(winston, demespec.uuid, index, Selection(2))
    Client.cast_vote!(dorian, demespec.uuid, index, Selection(3), force=true)
    Client.cast_vote!(dorian, demespec.uuid, index, Selection(1))
    Client.cast_vote!(winston, demespec.uuid, index, Selection(1))
    

    return
end


function ReviseHandler(handle)
    req -> begin
        Revise.revise()
        invokelatest(handle, req)
    end
end



PeaceFounderAdmin.serve(server_middleware=[ReviseHandler], admin_middleware=[ReviseHandler]) do

    init_test_state()

end

