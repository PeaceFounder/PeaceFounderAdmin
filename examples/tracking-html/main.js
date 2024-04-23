function format_timestamp(isoString) {

    // Convert the string to a Date object
    let date = new Date(isoString + "Z");

    // Format the date part
    let formattedDate = date.toLocaleDateString('en-GB', {
        day: '2-digit',    // "22"
        month: 'short',    // "Apr"
        year: 'numeric'    // "2024"
    });

    // Format the time part
    let formattedTime = date.toLocaleTimeString('en-GB', {
        hour: '2-digit',       // "21" (note: ensure to adjust according to your local timezone)
        minute: '2-digit',     // "32"
        hour12: false          // 24-hour format
    });

    // Combine both parts
    let nicelyFormatted = `${formattedDate}, ${formattedTime}`;

    return nicelyFormatted
}

function hex2bytes(hexString) {
    // Check if the hex string has an odd length and pad with zero if necessary
    if (hexString.length % 2 !== 0) {
        hexString = "0" + hexString;
    }

    // Create a Uint8Array with half the length of the hex string
    const bytes = new Uint8Array(hexString.length / 2);

    // Convert each pair of hex characters to a byte
    for (let i = 0, j = 0; i < hexString.length; i += 2, j++) {
        bytes[j] = parseInt(hexString.substring(i, i + 2), 16);
    }

    return bytes;
}

function bytes2hex(uint8Array) {
    // Initialize an empty array to collect hexadecimal values
    let hex = [];

    // Iterate over each byte in the Uint8Array
    for (let i = 0; i < uint8Array.length; i++) {
        // Convert each byte to a hexadecimal string
        let byteHex = uint8Array[i].toString(16);

        // Pad single digit hex numbers with a leading zero
        byteHex = byteHex.length === 1 ? '0' + byteHex : byteHex;

        // Append the hex string to the array
        hex.push(byteHex);
    }

    // Join all hex strings into a single hexadecimal string
    return hex.join('');
}

function decodeCrockfordBase32(encoded) {
    const crockfordAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    const valueMap = {};

    // Populate the value map with indices and handle similar characters
    for (let i = 0; i < crockfordAlphabet.length; i++) {
        valueMap[crockfordAlphabet[i]] = i;
    }
    valueMap['O'] = valueMap['0'];
    valueMap['I'] = valueMap['1'];
    valueMap['L'] = valueMap['1'];
    valueMap['U'] = valueMap['V'];

    // Clean the input (remove hyphens, normalize to uppercase)
    encoded = encoded.toUpperCase().replace(/-/g, '');

    let bits = 0;
    let value = 0;
    const output = [];

    // Decode the input
    for (let char of encoded) {
        const n = valueMap[char];
        if (n === undefined) continue; // skip invalid characters

        value = (value << 5) | n; // Shift the previous bits left and add new bits
        bits += 5;

        while (bits >= 8) {
            const shift = bits - 8;
            output.push((value >> shift) & 0xFF); // Extract the top byte
            value &= (1 << shift) - 1; // Mask off the bits that were pushed out
            bits -= 8;
        }
    }

    return new Uint8Array(output);
}


function CrockfordDecode(encoded) {
    let cleaned_string = encoded.replace(/-/g, '');    
    let bytes = decodeCrockfordBase32(cleaned_string);
    let hex = bytes2hex(bytes);
    return CryptoJS.enc.Hex.parse(hex);    
}
