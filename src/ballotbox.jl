
struct VoteView
    CAST::Int
    TIMESTAMP::String
    PSEUDONYM::String
    SEQ::Int
    SELECTION::String
    STATUS::String
end


using PeaceFounder.Model: CastRecord, Proposal, BraidReceipt, Pseudonym, Selection



function create_view(votes::Vector{CastRecord}, proposal::Proposal, braid::BraidReceipt)
    # It would be better to refactor this method on ballotbox

    # I would use the same thing in the 
    #pseudonyms = sort!([Model.output_members(braid)...])
    pseudonyms = Model.output_members(braid) # Using voters may be better
    
    table = VoteView[]


    for (cast, v) in enumerate(votes)

        timestamp = Dates.format(v.timestamp, "d u yyyy, HH:MM")
        
        pindex = findfirst(x -> x == v.vote.seal.pbkey, pseudonyms)
        seq = v.vote.seq

        selection = string(v.vote.selection.option)

        next_vote = findnext(x -> x.vote.seal.pbkey == v.vote.seal.pbkey && x.vote.seq >= v.vote.seq, votes, cast + 1)


        if Model.isconsistent(v.vote.selection, proposal.ballot)

            if isnothing(next_vote)
                status = """<span class="fw-bold text-success">Valid</span>"""
            else
                status = """<span class="fw-bold text-warning">Overriden</span>""" # Overruled (used by higher outhorithy), Overloaded
            end

        else
            status = """<span class="fw-bold text-danger">Malformed</span>"""
        end


        vote_view = VoteView(cast, timestamp, string(pindex), seq, selection, status)

        push!(table, vote_view)
    end

    return table
end


@get "/braidchain/{index}/ballotbox" function(req::Request, index::Int)
    
    data = Dict()

    data["INDEX"] = index

    proposal = Mapper.BRAID_CHAIN[].ledger[index]
    bbox = Mapper.ballotbox(proposal.uuid)
    braid = Mapper.BRAID_CHAIN[].ledger[proposal.anchor.index]

    data["TABLE"] = create_view(bbox.ledger, proposal, braid)

    return render(joinpath(TEMPLATES, "proposal_ballotbox.html"), data) |> html
end

using Printf


function format_percent(fraction)

    number = fraction * 100

    if isinteger(number)
        return (@sprintf("%d", number)) * "%"  # Integer formatting
    else
        return (@sprintf("%.1f", number)) * "%"  # One decimal place formatting
    end
end

@get "/braidchain/{index}/tally" function(req::Request, index::Int)

    data = Dict()    

    data["INDEX"] = index
    
    proposal = Mapper.BRAID_CHAIN[].ledger[index]
    bbox = Mapper.ballotbox(proposal.uuid)

    data["VOTES_COUNT"] = bbox.commit.state.index

    # Assumes that only valid pseudonyms have signed the votes, which is true
    # for a record to be inlcuded into ballotbox ledger.
    tally_bitmask = PeaceFounder.Model.tallyview(bbox.ledger, proposal.ballot)
    
    data["VALID_VOTES_COUNT"] = count(tally_bitmask)


    data["PARTICIPATION"] = format_percent(count(tally_bitmask)/proposal.anchor.member_count)
    
    _tally = tally(proposal.ballot, PeaceFounder.Model.selections(bbox.ledger[tally_bitmask]))

    lines = ""

    for (o, t) in zip(proposal.ballot.options, _tally.data)

        lines *= """<p style="margin-bottom: 0;">$o : $t</p>\n"""

    end

    #data["TALLY"] = string(_tally)
    data["TALLY"] = lines
    

    data["BALLOTBOX_TREE_ROOT"] = chunk_string(string(bbox.commit.state.root), 8) |> uppercase # bytes2hex may be a better here
    
    
    if isnothing(bbox.commit.state.tally)

        data["RELEASES"] = "Scheduled on " * Dates.format(proposal.closed, "d u yyyy, HH:MM")

    else
        data["RELEASES"] = """Released on <span id="under-construction">6 Jan 2024, 23:00</span>"""
        data["ACTION"] = """disabled="disabled" """

    end


    return render(joinpath(TEMPLATES, "proposal_tally.html"), data) |> html
end


@post "/braidchain/{index}/tally" function(req::Request, index::Int)
    
    proposal = Mapper.BRAID_CHAIN[].ledger[index]
    Mapper.tally_votes!(proposal.uuid)

    return Response(301, Dict("Location" => "/braidchain/$index/tally"))
    #return Response(301, Dict("Location" => "/braidchain/$index/tally"))
end
