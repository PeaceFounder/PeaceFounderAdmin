function showFileNameDeme() {
    var fileInput = document.getElementById('demePicker');
    var fileNameDisplay = document.getElementById('deme');

    if (fileInput.files.length > 0) {
        var fileName = fileInput.files[0].name;
        fileNameDisplay.textContent = fileName;
    }
}

function showFileNameLedger() {
    var fileInput = document.getElementById('ledgerPicker');
    var fileNameDisplay = document.getElementById('ledger');

    if (fileInput.files.length > 0) {
        var fileName = fileInput.files[0].name;
        fileNameDisplay.textContent = fileName;
    }
}


function submitForm() {

    // Need to check that a deme record file is found.
    // Need to select this
    let hasError = false; //!checkPasswordStrength() || !checkPasswordEquality()

    if (hasError) {

        let btn = document.getElementById('submitBtn');
        btn.classList.add('shake');

        // Optionally, remove the class after the animation ends
        btn.addEventListener('animationend', () => {
            btn.classList.remove('shake');
        });
    } else {

        window.location.assign("summary.html");

    }
    
}
