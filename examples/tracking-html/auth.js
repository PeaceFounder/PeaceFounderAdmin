function signRequest(host,
                     method,      // GET, PUT, POST, DELETE
                     url,         // path+query
                     body,        // request body (undefined of none)
                     credential,  // access key id
                     secret)      // access key value as byte vector
{
    var verb = method.toUpperCase();
    var utcNow = new Date().toUTCString(); // TODO: exact time needs to be obfuscated for anonymity
    var contentHash = CryptoJS.SHA256(body).toString(CryptoJS.enc.Base64);

    //
    // SignedHeaders
    var signedHeaders = "x-ms-date;host;x-ms-content-sha256"; // Semicolon separated header names

    //
    // String-To-Sign
    var stringToSign =
        verb + '\n' +                              // VERB
        url + '\n' +                               // path_and_query
        utcNow + ';' + host + ';' + contentHash;   // Semicolon separated SignedHeaders values


    // Signature
    //var signature = CryptoJS.HmacSHA256(stringToSign, CryptoJS.enc.Base64.parse(secret)).toString(CryptoJS.enc.Base64);
    var signature = CryptoJS.HmacSHA256(stringToSign, secret).toString(CryptoJS.enc.Base64);

    // Result request headers
    return [
        { name: "x-ms-date", value: utcNow },
        { name: "x-ms-content-sha256", value: contentHash },
        { name: "Authorization", value: "HMAC-SHA256 Credential=" + credential + "&SignedHeaders=" + signedHeaders + "&Signature=" + signature }
    ];

}


//function verifyRequest(request, secretBase64) {
function verifyRequest(request, secret) {
    const { method, url, headers, body } = request;

    // Extract the necessary headers
    const utcNow = headers['x-ms-date'];
    const contentHashReceived = headers['x-ms-content-sha256'];
    const authorizationHeader = headers['authorization'] ?? headers['Authorization'];
    const host = headers['host'] ?? headers['Host'];

    // Recreate the content hash for verification
    const contentHash = body ? CryptoJS.SHA256(body).toString(CryptoJS.enc.Base64) : CryptoJS.enc.Base64.stringify(CryptoJS.SHA256(''));

    // Verify content hash
    if (contentHash !== contentHashReceived) {
        return false; // Hash mismatch indicates the body was altered
    }

    // Extract signature from the Authorization header
    // Assuming the Authorization header format is "HMAC-SHA256 Credential=credential&SignedHeaders=signedHeaders&Signature=signature"
    const signatureReceived = authorizationHeader.split('&Signature=')[1];
    if (!signatureReceived) {
        return false; // Signature not found in the Authorization header
    }

    // Recreate string to sign
    const signedHeaders = "x-ms-date;host;x-ms-content-sha256";
    const stringToSign = method.toUpperCase() + '\n' + url + '\n' + utcNow + ';' + host + ';' + contentHash;

    // Decode the base64 secret for signing
    //const secret = CryptoJS.enc.Base64.parse(secretBase64);

    // Recreate the signature using the secret
    const signature = CryptoJS.HmacSHA256(stringToSign, secret).toString(CryptoJS.enc.Base64);

    // Verify the recreated signature against the received signature
    return signature === signatureReceived;
}

// key now is passed as a vector of bytes
function fetchAuthorized(action, request, key) {
    const {method, headers, body} = request; 

    // Parse the URL
    const url = new URL(action);
    const host = url.host;
    const path = url.pathname;

    // Deriving credential as a hash from the key
    let credential = CryptoJS.SHA256(key).toString(CryptoJS.enc.Base64);

    let authHeaders = signRequest(host, method, path, body, credential, key);

    headers['Host'] = host;

    return fetch(action, {
        method: method,
        headers: authHeaders.reduce((acc, header) => {
            acc[header.name] = header.value;
            return acc;
        }, headers),
        body: body
    }).then(response => {


        if (response.status === 401) {
            return response.text().then(message => {
                // Construct an error message including the server's response
                const errorMessage = message || "Unauthorized: Access is denied due to invalid credentials.";
                throw new Error(errorMessage);
            });
        }

        // Make a copy of the response to read the body without consuming it
        const clonedResponse = response.clone();
        
        // Now, use the cloned response for authorization check
        return clonedResponse.text().then(body => {
            let responseHeaders = {};

            // Iterate over response headers and collect them
            response.headers.forEach((value, name) => {
                responseHeaders[name] = value;
            });

            responseHeaders['host'] = host;

            if (verifyRequest({
                method: "REPLY",
                url: path,
                body: body,
                headers: responseHeaders
            }, key)) {
                console.log("Response Authorized");
                // Return the original response object
                return response;
            } else {
                // Throw an error or handle unauthorized response
                throw new Error("Response Unauthorized or Verification Failed");
            }
        });
    }).catch(error => {
        console.error("Error in fetch_authorized:", error);
        throw error; // Re-throw or handle as needed
    });
}
