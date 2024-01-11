include("../src/PeaceFounderAdmin.jl")

using Dates
using UUIDs
using HTTP

using PeaceFounder
using PeaceFounder: Client, Mapper
using PeaceFounder.Model: CryptoSpec, generate, Signer, DemeSpec, id, approve, Ballot, Proposal, Selection


module Mock
# This is a simple hack for the testing to go through. There is no intention to upstream it

using Setfield
using PeaceFounder.Model: digest, Vote, seal, generator, Signer, Digest, Proposal, Selection, hasher

import PeaceFounder

function PeaceFounder.Model.vote(proposal::Proposal, seed::Digest, selection::Selection, signer::Signer; seq = 1)

    #@assert isconsistent(selection, proposal.ballot)

    proposal_digest = digest(proposal, hasher(signer.spec))

    #_seq = seq(signer, proposal_digest) + 1

    vote = Vote(proposal_digest, seed, selection, seq)
    approval = seal(vote, generator(proposal), signer::Signer)
    
    return @set vote.approval = approval
end

end

# For testing purposes
function init_test_state()

    title = "Some Community"
    hash = "sha256"
    group = "EC: P_192"

    crypto = CryptoSpec(hash, group)

    guardian = generate(Signer, crypto)
    proposer = generate(Signer, crypto)

    PeaceFounderAdmin.PROPOSER[] = proposer # 
    
    Mapper.initialize!(crypto)

    roles = Mapper.system_roles()
    
    spec = DemeSpec(;
                    uuid = UUIDs.uuid4(),
                    title = title,
                    crypto = crypto,
                    guardian = id(guardian),
                    recorder = roles.recorder,
                    recruiter = roles.recruiter,
                    braider = roles.braider,
                    proposer = id(proposer),
                    collector = roles.collector
                    ) |> approve(guardian)
    

    Mapper.capture!(spec)

    PeaceFounderAdmin.SETTINGS["SMTP_EMAIL"] = "demeregistrar@inbox.lv"
    PeaceFounderAdmin.SETTINGS["SMTP_SERVER"] = "smtps://mail.inbox.lv:465"
    PeaceFounderAdmin.SETTINGS["SMTP_PASSWORD"] = ENV["REGISTRAR_PASSWORD"] 


    # For debugging the Electoral Roll view
    # create_profile("Peter Parker", "DEBUG").state = Invited(false)
    # create_profile("Harry Potter", "DEBUG").state = Invited(true)
    # create_profile("Sherlock Holmes", "DEBUG").state = Admitted(false)
    # create_profile("Frodo Baggins", "DEBUG").state = Admitted(true)
    # create_profile("Walter White", "DEBUG").state = Registered(3, false)
    # create_profile("Indiana Jones", "DEBUG").state = Registered(3, true)
    # create_profile("Luke Skywalker", "DEBUG").state = Terminated(4, 6)


    profile = PeaceFounderAdmin.create_profile("Lisbeth Salander", "DEBUG")
    invite = PeaceFounderAdmin.create_invite(profile)
    lisbeth = Client.DemeClient()
    Client.enroll!(lisbeth, invite, key = 4)

    profile = PeaceFounderAdmin.create_profile("Dorian Gray", "DEBUG")
    invite = PeaceFounderAdmin.create_invite(profile)
    dorian = Client.DemeClient()
    Client.enroll!(dorian, invite, key = 3)
    
    profile = PeaceFounderAdmin.create_profile("Winston Smith", "DEBUG") #Holly Golightly
    invite = PeaceFounderAdmin.create_invite(profile)
    winston = Client.DemeClient() 
    Client.enroll!(winston, invite, key = 5) # need to look into key attribute a
    # Also randomness in ShuffleProofs seems to be fixated during compilation time and thus need to be improved.

    # Self-Braiding

    input_generator = Mapper.get_generator()
    input_members = Mapper.get_members()

    braidwork = Model.braid(input_generator, input_members, spec, spec, Mapper.BRAIDER[]) 

    Mapper.submit_chain_record!(braidwork)

    # Adding of a proposal

    commit = Mapper.BRAID_CHAIN[].commit

    proposal = Proposal(
        uuid = UUIDs.uuid4(),
        summary = "Should the city ban all personal vehicle usage and invest in alternative forms of transportation such as public transit, biking and walking infrastructure?",
        description = "",
        ballot = Ballot(["Yes", "No"]),
        open = Dates.now(),
        closed = Dates.now() + Dates.Second(600),
        collector = roles.collector, # should be deprecated

        state = commit.state
    ) |> approve(PeaceFounderAdmin.PROPOSER[])


    index = Mapper.submit_chain_record!(proposal).proof.index

    #23424:sha256:
    # Adding few votes

    sleep(1)

    Client.update_deme!(lisbeth, spec.uuid)
    Client.update_deme!(dorian, spec.uuid)
    Client.update_deme!(winston, spec.uuid)
    
    Client.cast_vote!(lisbeth, spec.uuid, index, Selection(2))
    Client.cast_vote!(winston, spec.uuid, index, Selection(2))
    Client.cast_vote!(dorian, spec.uuid, index, Selection(3))
    Client.cast_vote!(dorian, spec.uuid, index, Selection(1))
    Client.cast_vote!(winston, spec.uuid, index, Selection(1))
    

    return
end


import HTTP

try
    global service = HTTP.serve!(PeaceFounder.Service.ROUTER, "0.0.0.0", 4584)

    init_test_state()

    # A method is forwarded fromm Oxygen implicitly
    PeaceFounderAdmin.serve(port=3221) 
finally 
    close(service)
end
