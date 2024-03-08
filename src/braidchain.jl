# braidchain


struct RecordView
    INDEX::Int
    TYPE::String
    TIMESTAMP::String
    ISSUER::String
    TYPE_LOWERCASE::String
end

RecordView(index, type, timestamp, issuer) = RecordView(index, type, timestamp, issuer, lowercase(type))


using PeaceFounder.Model: Transaction, DemeSpec, Membership, BraidReceipt, Proposal

function row_view(record::Transaction, i::Int)

    type = string(typeof(record))
    timestamp = "unimplemented"
    issuer = """<td><span class="fw-normal">unimplemented</span></td>"""

    return RecordView(i, type, timestamp, issuer)
end


function row_view(record::DemeSpec, i::Int)

    type = "DemeSpec"
    timestamp = Dates.format(record.seal.timestamp, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">Guardian</span></td>"""
    
    return RecordView(i, type, timestamp, issuer)
end


function row_view(record::Membership, i::Int)

    # MembershipCertificate is mor suitable than MemberPass
    # - More ceremonial and used for display or record-keeping. This is true as it is not directly used.
    # - Includes the member's name, date of issue, possibly the signatures of officials from the organization. Signatures are essential.
    # - Often issued once upon the initiation of membership and may not require renewal. It's more of a permanent record.


    type = "Membership"
    timestamp = Dates.format(record.admission.seal.timestamp, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Registrar</span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "member")
end


function row_view(record::BraidReceipt, i::Int) # Rename BraidWork to BraidReceipt

    type = "Braid Receipt"
    timestamp = Dates.format(record.approval.timestamp, "d u yyyy, HH:MM") #"unimplemented date"
    uuid = record.producer.uuid

    issuer = """<td style="padding-top:5px; padding-bottom:0px;"><span class="fw-normal">#1.Braider<div style="font-size: 10px;">$uuid</div></span></td>"""
    
    return RecordView(i, type, timestamp, issuer, "braid")
end


function row_view(record::Proposal, i::Int)

    type = "Proposal"
    timestamp = Dates.format(record.open, "d u yyyy, HH:MM")
    issuer = """<td><span class="fw-normal">#1.Proposer</span></td>"""

    return RecordView(i, type, timestamp, issuer)
end


@get "/braidchain" function(req::Request)
    
    #table = RecordView[row_view(r, i) for (i, r) in enumerate(Mapper.BRAID_CHAIN[].ledger) if r !(isa Union{Lot, NonceCommitment})]

    table = RecordView[row_view(r, i) for (i, r) in enumerate(Mapper.BRAID_CHAIN[].ledger)]
    
    return render(joinpath(TEMPLATES, "buletinboard.html"), Dict("TABLE"=>table)) |> html
end


@get "/braidchain/{index}/demespec" function(req::Request, index::Int)

    data = Dict()

    data["INDEX"] = index
    
    spec = Mapper.BRAID_CHAIN[].ledger[index]

    data["TITLE"] = spec.title
    data["UUID"] = string(spec.uuid)
    data["GROUP_NAME"] =  get_option_text(joinpath(TEMPLATES, "partials/group_specs.html"), PeaceFounder.Model.lower_groupspec(spec.crypto.group))

    data["HASH_NAME"] = get_option_text(joinpath(TEMPLATES, "partials/hash_specs.html"), string(spec.crypto.hasher))

    data["HASHER"] = string(spec.crypto.hasher)

    data["GENERATOR"] = chunk_string(string(spec.crypto.generator), 8) |> uppercase


    data["DEMESPEC_HASH"] = chunk_string(string(Model.digest(spec, spec.crypto.hasher)), 8) |> uppercase


    data["GUARDIAN"] = chunk_string(string(issuer(spec)), 8) |> uppercase

    data["BRAID_CHAIN"] = chunk_string(string(spec.recorder), 8) |> uppercase

    data["BALLOTBOX"] = chunk_string(string(spec.collector), 8) |> uppercase

    data["REGISTRAR"] = chunk_string(string(spec.registrar), 8) |> uppercase

    data["PROPOSER"] = chunk_string(string(spec.proposer), 8) |> uppercase

    data["BRAIDER"] = chunk_string(string(spec.braider), 8) |> uppercase

    data["ISSUE_DATE"] = format_date_ordinal(spec.seal.timestamp)
    
    return render(joinpath(TEMPLATES, "deme.html"), data) |> html
end

@get "/braidchain/{index}/member" function(req::Request, index::Int)

    data = Dict()
    data["INDEX"] = index

    record = Mapper.BRAID_CHAIN[].ledger[index]

    data["GENERATOR"] = findprev(x -> x isa BraidReceipt || x isa DemeSpec, Mapper.BRAID_CHAIN[].ledger, index - 1)
    data["TICKETID"] = chunk_string(string(record.admission.ticketid), 8) |> uppercase
    data["IDENTITY"] = chunk_string(string(record.admission.id), 8) |> uppercase
    data["ISSUE_TIMESTAMP"] = Dates.format(record.admission.seal.timestamp, "d u yyyy, HH:MM")
    data["PSEUDONYM"] = chunk_string(string(record.pseudonym), 8) |> uppercase
    data["ACK_TIMESTAMP"] = format_date_ordinal(record.admission.seal.timestamp)

        #Dates.format(record.seal.timestamp, "d u yyyy, HH:MM")

    return render(joinpath(TEMPLATES, "member.html"), data) |> html
end


struct AliasView
    ALIAS::Int
    PSEUDONYM::String
end

@get "/braidchain/{index}/braid" function(req::Request, index::Int)
    
    data = Dict()

    data["INDEX"] = index

    braid = Mapper.BRAID_CHAIN[].ledger[index]

    data["DEME_TITLE"] = braid.producer.title
    data["DEME_UUID"] = braid.producer.uuid
    data["HASHER"] = string(braid.producer.crypto.hasher)

    data["DEMESPEC_HASH"] = chunk_string(string(Model.digest(braid.producer, braid.producer.crypto.hasher)), 8) |> uppercase


    pseudonyms = sort!([Model.output_members(braid)...])

    data["OUTPUT_GENERATOR"] = chunk_string(string(Model.output_generator(braid)), 8) |> uppercase
    data["TABLE"] = [AliasView(i, chunk_string(string(p), 8) |> uppercase) for (i, p) in enumerate(pseudonyms)]

    data["MEMBER_COUNT"] = length(pseudonyms)


    data["INPUT_GENERATOR"] = findprev(x -> x isa BraidReceipt || x isa DemeSpec, Mapper.BRAID_CHAIN[].ledger, index - 1)

    new_members = [i for (i, r) in enumerate(Mapper.BRAID_CHAIN[].ledger) if r isa Membership && i > data["INPUT_GENERATOR"]]

    data["ANONIMITY_THRESHOLD_GAIN"] = length(new_members)

    data["ISSUE_DATE"] = format_date_ordinal(braid.approval.timestamp)


    new_member_string = join(["#$i" for i in new_members], ", ")
    
    
    if Mapper.BRAID_CHAIN[].ledger[data["INPUT_GENERATOR"]] isa BraidReceipt
        data["INPUT_PSEUDONYMS"] = "#" * string(data["INPUT_GENERATOR"]) * "..." * (!isempty(new_members) ? ", " * new_member_string : "")
    else
        data["INPUT_PSEUDONYMS"] = new_member_string
    end
    #findprev(x -> x isa Braid || x isa DemeSpec, Mapper.BRAID_CHAIN[].ledger, index)


    return render(joinpath(TEMPLATES, "braid.html"), data) |> html
end

@get "/braidchain/{index}/proposal" function(req::Request, index::Int)
    
    record = Dict()
    record["INDEX"] = index

    proposal = Mapper.BRAID_CHAIN[].ledger[index]

    record["TITLE"] = proposal.summary
    record["UUID"] = proposal.uuid
    record["OPENS"] = Dates.format(proposal.open, "d u yyyy, HH:MM")
    record["CLOSES"] = Dates.format(proposal.closed, "d u yyyy, HH:MM")
    record["ANCHOR"] = proposal.anchor.index
    record["MEMBER_COUNT"] = proposal.anchor.member_count

    # %sha256 and such could be used for denoting hash type

    record["BRAIDCHAIN_ROOT"] = join(["#$(proposal.anchor.index)", chunk_string(string(proposal.anchor.root), 8) |> uppercase], ":")
    record["ELECTORAL_ROLL_ROOT"] = join(["§334", chunk_string(string(proposal.anchor.root), 8) |> uppercase], ":")

    record["DESCRIPTION"] = proposal.description
    record["BALLOT_TYPE"] = "Simple Ballot"
    #record["BALLOT"] = string(proposal.ballot)

    record["BALLOT"] = join(["""<p style="margin-bottom: 0;"> $i </p>""" for i in proposal.ballot.options],"\n")

    record["ISSUE_DATE"] = format_date_ordinal(proposal.approval.timestamp)

    return render(joinpath(TEMPLATES, "proposal_record.html"), record) |> html
end


@get "/braidchain/{index}/lot" function(req::Request, index::Int)
    
    data = Dict("INDEX"=>index)    

    return Response(301, Dict("Location" => "/braidchain"))    
end


@get "/braidchain/{index}/noncecommitment" function(req::Request, index::Int)
    
    data = Dict("INDEX"=>index)

    return Response(301, Dict("Location" => "/braidchain"))
end


@get "/braidchain/{index}" function(req::Request, index::Int)

    record = Mapper.BRAID_CHAIN[].ledger[index]

    if record isa DemeSpec
        return Response(301, Dict("Location" => "/braidchain/$index/demespec"))
    elseif record isa Member
        return Response(301, Dict("Location" => "/braidchain/$index/member"))
    elseif record isa Proposal
        return Response(301, Dict("Location" => "/braidchain/$index/proposal"))
    elseif record isa BraidReceipt
        return Response(301, Dict("Location" => "/braidchain/$index/braid"))
    else record isa Union{Lot, NonceCommitment}
        return  Response(301, Dict("Location" => "/braidchain"))
    end
end


@get "/braidchain/new-braid" function(req::Request)

    spec = Mapper.get_demespec()

    data = Dict()

    data["TITLE"] = spec.title
    data["UUID"] = spec.uuid
    data["GUARDIAN"] = chunk_string(string(issuer(spec)), 8) |> uppercase

    return render(joinpath(TEMPLATES, "new-braid.html"), data) |> html
end


@post "/braidchain/new-braid" function(req::Request)

    spec = Mapper.get_demespec()

    input_generator = Mapper.get_generator()
    input_members = Mapper.get_members()

    braidwork = Model.braid(input_generator, input_members, spec, spec, Mapper.BRAIDER[]) 

    Mapper.submit_chain_record!(braidwork)

    return Response(301, Dict("Location" => "/braidchain"))
end



@get "/braidchain/new-proposal" function(req::Request)

    defaults = Dict()

    defaults["TODAY"] = Dates.format(Dates.today(), "dd/mm/yyyy")
    defaults["TOMORROW"] = Dates.format(Dates.today() + Dates.Day(1), "dd/mm/yyyy")
    defaults["CURRENT_ANCHOR"] = findlast(x -> x isa BraidReceipt, Mapper.BRAID_CHAIN[].ledger)

    return render(joinpath(TEMPLATES, "new-proposal.html"), defaults) |> html
end


using PeaceFounder.Model: generator, root, members, ChainState, BraidChain


function _state(chain::BraidChain, index::Int)

    g = generator(chain, index)
    r = root(chain, index)
    member_count = length(members(chain, index))

    return ChainState(index, r, g, member_count)
end




@post "/braidchain/new-proposal" function(req::Request)

     (; title, description, open_date, open_time, close_date, close_time, ballot_type, ballot, anchor, release_date, release_time) = json(req)

    isempty(open_time) && (open_time="00:00")
    isempty(close_time) && (close_time="00:00")

    isempty(release_date) && (release_date=close_date)
    isempty(release_time) && (release_time=close_time)


    if isempty(anchor)
        anchor_index = findlast(x -> x isa BraidReceipt, Mapper.BRAID_CHAIN[].ledger)
    else
        if anchor[1] == "#"
            anchor_index = parse(Int, anchor[2:end])
        else
            anchor_index = parse(Int, anchor)
        end
    end

    # I need to retrieve a state of the braidchain
    anchor_state = _state(Mapper.BRAID_CHAIN[], anchor_index)

    open_datetime = DateTime(join([open_date, open_time], " "), "dd/mm/yyyy HH:MM")
    close_datetime = DateTime(join([close_date, close_time], " "), "dd/mm/yyyy HH:MM")
    release_datetime = DateTime(join([release_date, release_time], " "), "dd/mm/yyyy HH:MM")

    parsed_ballot = Ballot(split(ballot, "\n"))

    #roles = Mapper.system_roles()

    spec = Mapper.get_demespec()

    proposal = Proposal(
        uuid = UUIDs.uuid4(),
        summary = title, # need to rename as title
        description = description,
        ballot = parsed_ballot,
        open = open_datetime,
        closed = close_datetime,
        collector = spec.collector, # should be deprecated
        
        state = anchor_state # anchor, because the state is in the type
    ) |> approve(Mapper.PROPOSER[])


    Mapper.submit_chain_record!(proposal)

    return Response(301, Dict("Location" => "/braidchain"))
end

