using Test

import PeaceFounder.Server.Service: ROUTER
import PeaceFounder.Server: Mapper
import PeaceFounder.Core.Model: CryptoSpec, generate, approve, Signer, DemeSpec, TicketID

include("../examples/integration/setup.jl")
import .IntegrationSetup

include("../examples/integration/invite.jl")
import .InviteCode

crypto = CryptoSpec("sha256", "EC: P_192")
GUARDIAN = generate(Signer, crypto)

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
             ) |> approve(GUARDIAN) 

end


InviteCode.TOKEN_KEY = Mapper.token_key()
InviteCode.TOKEN_LENGTH = Mapper.token_nlen()

ticketid = rand(UInt8, 16)
invite = InviteCode.create_profile(ROUTER, "Alice", "alice@email.com", ticketid)

@test invite == string(Mapper.enlist_ticket(TicketID(ticketid)))
