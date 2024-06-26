using Printf
using PeaceFounder.Core.Model: CastRecord, Proposal, BraidReceipt, Pseudonym, Selection, voters
using PeaceFounder.Server.Controllers: BallotBoxController
using PeaceFounder.StaticSets: findindex


struct VoteView
    CAST::Int
    TIMESTAMP::String
    PSEUDONYM::String
    SEQ::Int
    SELECTION::String
    STATUS::String
end


function create_view(bbox::BallotBoxController)

    table = VoteView[]

    bitmask = Model.tally_bitmask(bbox.ledger)

    for (cast, v) in enumerate(bbox.ledger)

        timestamp = Dates.format(v.timestamp |> local_time, "d u yyyy, HH:MM")
        
        alias = v.alias
        anchor_index = bbox.ledger.proposal.anchor.index

        seq = v.vote.seq

        if bitmask[cast]
            status = """<span class="fw-bold text-success">Valid</span>"""
        else
            if Model.isconsistent(v.vote.selection, bbox.ledger.proposal.ballot)
                # Overruled (used by higher outhorithy), Overloaded
                status = """<span class="fw-bold text-warning">Overriden</span>""" 
            else
                status = """<span class="fw-bold text-danger">Malformed</span>"""
            end
        end
        
        selection = string(v.vote.selection.option)
        vote_view = VoteView(cast, timestamp, "#$anchor_index.$alias", seq, selection, status)

        push!(table, vote_view)
    end

    return table
end


@get "/braidchain/{index}/ballotbox" function(req::Request, index::Int)
    
    proposal = Mapper.BRAID_CHAIN.ledger[index]
    bbox = Mapper.get_ballotbox(proposal.uuid)

    return render_template("proposal_ballotbox.html") <| [
        :INDEX => index,
        :TABLE => create_view(bbox)
    ]
end


function format_percent(fraction)

    number = fraction * 100

    if isinteger(number)
        return (@sprintf("%d", number)) * "%"  # Integer formatting
    else
        return (@sprintf("%.1f", number)) * "%"  # One decimal place formatting
    end
end

using Infiltrator

@get "/braidchain/{index}/tally" function(req::Request, index::Int)

    proposal = Mapper.BRAID_CHAIN.ledger[index]
    bbox = Mapper.get_ballotbox(proposal.uuid)

    # Assumes that only valid pseudonyms have signed the votes, which is true
    # for a record to be inlcuded into ballotbox ledger.
    #tally_bitmask = Model.tallyview(bbox.ledger, proposal.ballot)
    
    tally_bitmask = Model.tally_bitmask(bbox.ledger)
    
    #_tally = tally(proposal.ballot, Model.selections(bbox.ledger[tally_bitmask]))
    _tally = tally(bbox.ledger)

    lines = ""

    for (o, t) in zip(proposal.ballot.options, _tally.data)

        lines *= """<p style="margin-bottom: 0;">$o : $t</p>\n"""

    end

    if isnothing(bbox.commit.state.tally)
        releases = "Scheduled on " * Dates.format(proposal.closed, "d u yyyy, HH:MM")
    else
        releases = """Released on <span id="under-construction">6 Jan 2024, 23:00</span>"""
    end

    return render_template("proposal_tally.html") <| [
        :INDEX => index,
        :VOTES_COUNT => bbox.commit.state.index,
        :VALID_VOTES_COUNT => count(tally_bitmask),
        :PARTICIPATION => format_percent(count(tally_bitmask)/proposal.anchor.member_count),
        :TALLY => lines,
        :BALLOTBOX_TREE_ROOT => chunk_string(string(bbox.commit.state.root), 8) |> uppercase, # bytes2hex may be a better here
        :RELEASES => releases,
        :ACTION => isnothing(bbox.commit.state.tally) ? "" : """disabled="disabled" """
    ]
end


@post "/braidchain/{index}/tally" function(req::Request, index::Int)
    
    proposal = Mapper.BRAID_CHAIN.ledger[index]
    Mapper.tally_votes!(proposal.uuid)

    return Response(301, Dict("Location" => "/braidchain/$index/tally"))
end
