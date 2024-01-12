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

## Voting

![](docs/assets/peacefounder-voting.webp)

## BraidChain Ledger

![](docs/assets/peacefounder-braidchain.webp)
