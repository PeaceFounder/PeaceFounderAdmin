# PeaceFounderAdmin
Admin panel for PeaceFounder e-voting system

## System Setup

![](docs/assets/peacefounder-setup.webp)

```
curl -LOJ https://github.com/PeaceFounder/PeaceFounderAdmin/releases/download/v0.0.1/peacefounder-server-0.0.1-x64.snap
```

```
snap install --devmode peacefounder-server-0.0.1-x64.snap
```

The admin panel is hosted on `http://127.0.0.1:3221` which is not accessable from the outside wheras on `http://0.0.0.0:4585` is the public entry point. To access the admin panel remotely use ssh to forward the localhost port which provides secure authentification:

```
ssh -L 2332:127.0.0.1:3221 user@192.168.1.16
```

The system does not need to have a TLS certificate for security as all requests are signed by coresponding parties. It in fact can be harmful as it can lower the barrier under which system can made unavailable with DDOS as TLS session resumption must be disabled to ensure anonimity for the voters and every session would need a new key exchange which depends on comparativellly expensive group operation. However at the moment performance of HTTP request processing is not optimized and it can be added without costs. The PeaceFounder client will work if the server will be put behind NGINX.

## Member Registration

![](docs/assets/peacefounder-registration.webp)

Member registration happens over email over which a token is sent. In contrast to JWT tokens that are added to the header is TLS connection, the token here is used as `HMAC(body|timestamp, token)` key over which a request is authetificated. For the server to recognize from where the request comes from a `Hash(token)` is added to the header (now it is a ticketid, but it will be made obselete shortly). 

When invite is entered into the PeaceFounder client a following steps are performed : 

- The device will retrieve deme specification parameters from provided address which will be compared with hash in the invite
- The cryptographic parameters will be initialised and a new key pair generated.
- The public key will be authetificated with HMAC using the invite tooken and will be sent to the deme server which shall return the ppublic key signed by the registrar which whe shall reffer as admission certificate.
- In the last step device retrieves the current braidchain generator and computes it's pseudonym. This together with admission certificate is signed by the member's private key which consistutes a member certificate. The member certificate is sent to the braidchain until History Tree inclusion proof is received concluding the process. If generator has changed a new pseudonym is recomputed.

To ensure electoral roll auditability, the received invites are signed by the members with the corepsonding membership certificate registrartion index and returns the document to the guardian. This is sufficient as invite contains demespec ensuring that registration happens with the claimed entity and the member index ensures as confirmation that registration had been successful. This makes the evoting system universally applicable around the world wherever some sort of digital identity infrastructure exists.

## Voting

![](docs/assets/peacefounder-voting.webp)

After members are registered a braid needs to be generated. Multiple braids can be chained together to increase anonimity threshold - a minimum number of specific parties which needs to be compromised in order to discover how a member certificate is linked to it's pseudonym with which they cast their votes. Currently the maximum anonimity threshold is one as currently only self-braiding is implemented. In future the braiding will be possible between different demes. These could be fictional managed for particular vote or real communities distributed around the world. In the end a braid receipt is retrieved from the party verified for integrity with ZKP and is recorded in the braidchain. 

To initiate voting the guardian creates a new proposal. Proposal contains opening, closing time, title, description, ballot and an anchor. The anchor for the proposal is the index of a braid whose generator and pseudonyms are used. If the member is registered after the anchor it is excluded from the vote. Continious member registration and ability to do self braiding however shall prevent such exclusion from the vote. The anchor also enables to link two proposals together for fluid voting situations where members may have an option to change their vote in predetermined times during the representative serving term. 

## BraidChain Ledger

![](docs/assets/peacefounder-braidchain.webp)

BraidChain and BallotBox ledgers together form proof of ellection integrity which is made publically available. Wheras ballotbox ledger is rather simple containing votes signed by the voters pseudonym and do not affect the ballotbox state the braidchain is the opposite and contains many gems. While auditors can execute auditing program (will be developed shortly after record storage situation will be sorted) without any understanding of the datastructure behind the scenes in situations where an issue rises it is good to have a reference point and be able to communicate effectivelly about issues. 

Every record in the braidchain ledger has an issuer who have signed it with a digital signature. For the issuer's record to be included in the ledger it must have the coresponding authorisation. Public keys for them are listed in the DemeSpec record under roster section. In situations when party key needs to change an updated DemeSpec record can be issued signed with Guardians private key. It is planed that the Guardian's private key will be encrypted with a strong password created during setup wizard and stored in the deme record. Perhaps an alternative where multiple parties need to sign the record for it to be valid could be considered for higher stakes situations. One shall however remember that the only thing adversary can affect gaining full control is availability and register fake members who participate in the vote (additional risk though is that it never publishes the ballotbox). Both of theese actions are prevented with spontanous monitoring when members see that they are unable to receive confirmation that their vote had been included.
