using PeaceFounder.Core.Model: Transaction, DemeSpec, Membership, BraidReceipt, Proposal, generator, root, members, roll, ChainState, termination_bitmask
using PeaceFounder.Server.Controllers: BraidChainController


struct RecordView
    INDEX::Int
    TYPE::String
    TIMESTAMP::String
    ISSUER::String
    TYPE_LOWERCASE::String
end

RecordView(index, type, timestamp, issuer) = RecordView(index, type, timestamp, issuer, lowercase(type))


function row_view(record::Transaction, i::Int)

    type = string(typeof(record))
    timestamp = "unimplemented"
    issuer = """<td><span class="fw-normal">unimplemented</span></td>"""

    return RecordView(i, type, timestamp, issuer)
end


function row_view(record::DemeSpec, i::Int)

    type = "DemeSpec"
    timestamp = Dates.format(record.seal.timestamp |> local_time, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">Guardian</span></td>"""
    
    return RecordView(i, type, timestamp, issuer)
end


function row_view(record::Membership, i::Int)

    type = "Membership"
    timestamp = Dates.format(record.admission.seal.timestamp |> local_time, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Registrar</span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "member")
end

function row_view(record::Termination, i::Int)

    type = "Termination"
    timestamp = Dates.format(record.seal.timestamp |> local_time, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Registrar</span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "termination")
end

function row_view(record::BraidReceipt, i::Int) # Rename BraidWork to BraidReceipt

    type = "Braid Receipt"
    timestamp = Dates.format(record.approval.timestamp |> local_time, "d u yyyy, HH:MM") #"unimplemented date"
    uuid = record.producer.uuid

    issuer = """<td style="padding-top:5px; padding-bottom:0px;"><span class="fw-normal">#1.Braider<div style="font-size: 10px;">$uuid</div></span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "braid")
end


function row_view(record::Proposal, i::Int)

    type = "Proposal"
    timestamp = Dates.format(record.approval.timestamp |> local_time, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Proposer</span></td>"""

    return RecordView(i, type, timestamp, issuer)
end


@get "/braidchain" function(req::Request)

    table = RecordView[row_view(r, i) for (i, r) in enumerate(Mapper.BRAID_CHAIN.ledger)]
    
    return render_template("buletinboard.html") <| [
        :TABLE => table
    ]
end


@get "/braidchain/{index}/demespec" function(req::Request, index::Int)

    spec = Mapper.BRAID_CHAIN.ledger[index]

    return render_template("deme.html") <| [
        :INDEX => index,
        :TITLE => spec.title,
        :UUID => string(spec.uuid),
        :GROUP_NAME => get_option_text(joinpath(TEMPLATES, "partials/group_specs.html"), Model.lower_groupspec(spec.crypto.group)),
        :HASH_NAME => get_option_text(joinpath(TEMPLATES, "partials/hash_specs.html"), string(spec.crypto.hasher)),
        :HASHER => string(spec.crypto.hasher),
        :GENERATOR => chunk_string(string(spec.crypto.generator), 8) |> uppercase,
        :DEMESPEC_HASH => chunk_string(string(Model.digest(spec, spec.crypto.hasher)), 8) |> uppercase,
        :GUARDIAN => chunk_string(string(issuer(spec)), 8) |> uppercase,
        :BRAID_CHAIN => chunk_string(string(spec.recorder), 8) |> uppercase,
        :BALLOTBOX => chunk_string(string(spec.collector), 8) |> uppercase,
        :REGISTRAR => chunk_string(string(spec.registrar), 8) |> uppercase,
        :PROPOSER => chunk_string(string(spec.proposer), 8) |> uppercase,
        :BRAIDER => chunk_string(string(spec.braider), 8) |> uppercase,
        :ISSUE_DATE => format_date_ordinal(spec.seal.timestamp |> local_time)
    ]
end

@get "/braidchain/{index}/member" function(req::Request, index::Int)

    record = Mapper.BRAID_CHAIN.ledger[index]

    return render_template("member.html") <| [
        :INDEX => index,
        :GENERATOR => findprev(x -> x isa BraidReceipt || x isa DemeSpec, Mapper.BRAID_CHAIN.ledger.records, index - 1),
        :TICKETID => chunk_string(string(record.admission.ticketid), 8) |> uppercase,
        :IDENTITY => chunk_string(string(record.admission.id), 8) |> uppercase,
        :ISSUE_TIMESTAMP => Dates.format(record.admission.seal.timestamp |> local_time, "d u yyyy, HH:MM"),
        :PSEUDONYM => chunk_string(string(record.pseudonym), 8) |> uppercase,
        :ACK_TIMESTAMP => format_date_ordinal(record.admission.seal.timestamp |> local_time)
    ]
end

@get "/braidchain/{index}/termination" function(req::Request, index::Int)

    record = Mapper.BRAID_CHAIN.ledger[index]::Termination
    
    return render_template("termination.html") <| [
        :INDEX => index,
        :REGISTRATION => record.index == 0 ? "0 (Unregistered)" : record.index,
        :IDENTITY => chunk_string(string(record.identity), 8) |> uppercase,
        :ISSUE_DATE => format_date_ordinal(record.seal.timestamp |> local_time)
    ]
end

struct AliasView
    ALIAS::Int
    PSEUDONYM::String
end

@get "/braidchain/{index}/braid" function(req::Request, index::Int)

    braid = Mapper.BRAID_CHAIN.ledger[index]
    output_members = Model.output_members(braid)
    bitmask = termination_bitmask(Mapper.BRAID_CHAIN, index)

    if braid.reset
        input_generator = 1
        input_pseudonyms = ""
        new_members = [i for (i, r) in enumerate(view(Mapper.BRAID_CHAIN.ledger, 1:index)) if r isa Membership && !bitmask[i]]
    else
        input_generator = findprev(x -> x isa BraidReceipt || x isa DemeSpec, Mapper.BRAID_CHAIN.ledger.records, index - 1)
        new_members = [i for (i, r) in enumerate(view(Mapper.BRAID_CHAIN.ledger, 1:index)) if r isa Membership && i > input_generator && !bitmask[i]]
    end

    new_member_string = join(["#$i" for i in new_members], ", ")

    if Mapper.BRAID_CHAIN.ledger[input_generator] isa BraidReceipt
        input_pseudonyms = "#" * string(input_generator) * "..." * (!isempty(new_members) ? ", " * new_member_string : "")
    else
        input_pseudonyms = new_member_string
    end    

    return  render_template("braid.html") <| [
        :INDEX => index,
        :DEME_TITLE => braid.producer.title,
        :DEME_UUID => braid.producer.uuid,
        :HASHER => string(braid.producer.crypto.hasher),
        :DEMESPEC_HASH => chunk_string(string(Model.digest(braid.producer, braid.producer.crypto.hasher)), 8) |> uppercase,
        :OUTPUT_GENERATOR => chunk_string(string(Model.output_generator(braid)), 8) |> uppercase,
        :TABLE => [AliasView(i, chunk_string(string(p), 8) |> uppercase) for (i, p) in enumerate(output_members)],
        :RESET => braid.reset ? "True" : "False",
        :MEMBER_COUNT => length(output_members),
        :INPUT_GENERATOR => input_generator,
        :ANONIMITY_THRESHOLD_GAIN => braid.reset ? length(output_members) : length(new_members),
        :ISSUE_DATE => format_date_ordinal(braid.approval.timestamp |> local_time),
        :INPUT_PSEUDONYMS => input_pseudonyms
    ]
end

@get "/braidchain/{index}/proposal" function(req::Request, index::Int)

    proposal = Mapper.BRAID_CHAIN.ledger[index]

    return render_template("proposal_record.html") <| [
        :INDEX => index,
        :TITLE => proposal.summary,
        :UUID => proposal.uuid,
        :OPENS => Dates.format(proposal.open |> local_time, "d u yyyy, HH:MM"),
        :CLOSES => Dates.format(proposal.closed |> local_time, "d u yyyy, HH:MM"),
        :ANCHOR => proposal.anchor.index,
        :MEMBER_COUNT => proposal.anchor.member_count,
        :BRAIDCHAIN_ROOT => join(["#$(proposal.anchor.index)", chunk_string(string(proposal.anchor.root), 8) |> uppercase], ":"),
        :ELECTORAL_ROLL_ROOT => join(["§334", chunk_string(string(proposal.anchor.root), 8) |> uppercase], ":"),
        :DESCRIPTION => proposal.description,
        :BALLOT_TYPE => "Simple Ballot",
        :BALLOT => join(["""<p style="margin-bottom: 0;"> $i </p>""" for i in proposal.ballot.options],"\n"), # BALLOT_SPEC?
        :ISSUE_DATE => format_date_ordinal(proposal.approval.timestamp |> local_time)
    ]
end


@get "/braidchain/{index}" function(req::Request, index::Int)

    record = Mapper.BRAID_CHAIN.ledger[index]

    if record isa DemeSpec
        return Response(301, Dict("Location" => "/braidchain/$index/demespec"))
    elseif record isa Membership
        return Response(301, Dict("Location" => "/braidchain/$index/member"))
    elseif record isa Proposal
        return Response(301, Dict("Location" => "/braidchain/$index/proposal"))
    elseif record isa BraidReceipt
        return Response(301, Dict("Location" => "/braidchain/$index/braid"))
    end
end


@get "/braidchain/new-braid" function(req::Request)

    spec = Mapper.get_demespec()

    drop_count = length(members(Mapper.BRAID_CHAIN)) - length(roll(Mapper.BRAID_CHAIN))

    return render_template("new-braid.html") <| [
        :TITLE => spec.title,
        :UUID => spec.uuid,
        :DROP_COUNT => drop_count,
        :GUARDIAN => chunk_string(string(issuer(spec)), 8) |> uppercase
    ]
end


@post "/braidchain/new-braid" function(req::Request)

    spec = Mapper.get_demespec()

    reset = haskey(json(req), :reset)

    input_generator = Mapper.get_generator(; reset)
    input_members = Mapper.get_members(; reset)

    braidwork = Model.braid(input_generator, input_members, spec.crypto, spec, Mapper.BRAIDER; reset) 

    Mapper.submit_chain_record!(braidwork)

    return Response(301, Dict("Location" => "/braidchain"))
end


@get "/braidchain/new-proposal" function(req::Request)

    return render_template("new-proposal.html") <| [
        :TODAY => Dates.format(Dates.today(), "dd/mm/yyyy"), # LOCAL TIME HERE
        :TOMORROW => Dates.format(Dates.today() + Dates.Day(1), "dd/mm/yyyy"),
        :CURRENT_ANCHOR => findlast(x -> x isa BraidReceipt, Mapper.BRAID_CHAIN.ledger.records)
    ]
end

@post "/braidchain/new-proposal" function(req::Request)

     (; title, description, open_date, open_time, close_date, close_time, ballot_type, ballot, anchor, release_date, release_time) = json(req)

    isempty(open_time) && (open_time="00:00")
    isempty(close_time) && (close_time="00:00")

    isempty(release_date) && (release_date=close_date)
    isempty(release_time) && (release_time=close_time)


    if isempty(anchor)
        anchor_index = findlast(x -> x isa BraidReceipt, Mapper.BRAID_CHAIN.ledger.records)
    else
        if anchor[1] == "#"
            anchor_index = parse(Int, anchor[2:end])
        else
            anchor_index = parse(Int, anchor)
        end
    end

    # I need to retrieve a state of the braidchain
    anchor_state = Model.state(Mapper.BRAID_CHAIN, anchor_index)

    open_datetime = DateTime(join([open_date, open_time], " "), "dd/mm/yyyy HH:MM")
    close_datetime = DateTime(join([close_date, close_time], " "), "dd/mm/yyyy HH:MM")
    release_datetime = DateTime(join([release_date, release_time], " "), "dd/mm/yyyy HH:MM")

    parsed_ballot = Ballot(split(ballot, "\n"))

    spec = Mapper.get_demespec()

    proposal = Proposal(
        uuid = UUIDs.uuid4(),
        summary = title, # need to rename as title
        description = description,
        ballot = parsed_ballot,
        open = open_datetime |> utc_time,
        closed = close_datetime |> utc_time,
        collector = spec.collector, # should be deprecated
        
        state = anchor_state # anchor, because the state is in the type
    ) |> approve(Mapper.PROPOSER)

    Mapper.submit_chain_record!(proposal)

    return Response(301, Dict("Location" => "/braidchain"))
end

