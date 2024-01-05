// document.addEventListener("DOMContentLoaded", function() {
//     var rows = document.querySelectorAll("tr[data-href]");

//     rows.forEach(function(row) {
//         row.addEventListener("click", function() {
//             window.location.href = this.dataset.href;
//         });
//     });
// });


document.addEventListener("DOMContentLoaded", function() {
    var rows = document.querySelectorAll("tr[data-href]");
    //var rows = document.querySelectorAll("table tr");

    rows.forEach(function(row) {
        row.addEventListener("click", function() {
            // Remove highlight from all rows
            rows.forEach(r => r.classList.remove('selected'));
            
            // Highlight the clicked row
            this.classList.add('selected');

            // // Redirect if data-href is available
            if (this.dataset.href) {
                window.location.href = this.dataset.href;
            }

            // row.addEventListener("click", function() {
            //     //window.location.href = this.dataset.href;
            // });
        });
    });
});





document.addEventListener('DOMContentLoaded', function() {
    // Select all input elements with a 'value' attribute
    var inputsWithValue = document.querySelectorAll('input[value]');

    inputsWithValue.forEach(function(input) {
        // Set 'data-original-value' to the current value of the input
        input.setAttribute('data-original-value', input.value);
    });
    // ... rest of your event listener code ...
});



// Call the function when the DOM content is loaded
document.addEventListener('DOMContentLoaded', function () {
    // Select all textarea elements
    var textareas = document.querySelectorAll('textarea');

    textareas.forEach(function(textarea) {
        // Set 'data-original-value' to the current text content of the textarea
        if (textarea.value !== "") {
            textarea.setAttribute('data-original-value', textarea.value);
        }
    });
});


// For checkboxes we need to add explicit track-change class.
document.addEventListener('DOMContentLoaded', function() {
    var checkboxes = document.querySelectorAll('input[type="checkbox"].track-change');

    checkboxes.forEach(function(checkbox) {
        checkbox.setAttribute('data-original-checked', checkbox.checked.toString());
    });
});


document.addEventListener('DOMContentLoaded', function() {
    // Select all text inputs and checkboxes with the 'data-original-value' or 'data-original-checked' attributes
    var elements = document.querySelectorAll('input[data-original-value], input[type="checkbox"][data-original-checked], textarea[data-original-value]');

    elements.forEach(function(element) {
        // Determine the event type based on the input type
        var eventType = element.type === 'checkbox' ? 'change' : 'input';

        // Add an event listener for the determined event type
        element.addEventListener(eventType, function() {
            // Check the current state against the original state
            var isChanged = (element.type === 'checkbox') ?
                (this.checked.toString() !== this.getAttribute('data-original-checked')) :
                (this.value !== this.getAttribute('data-original-value'));

            // Add or remove the 'changed' class based on the comparison
            if (isChanged) {
                this.classList.add('changed');
            } else {
                this.classList.remove('changed');
            }
        });
    });

    // Optional: Handle form submission
    // var form = document.querySelector('form');
    // form.addEventListener('submit', function(event) {
    //     event.preventDefault(); // Prevent the default form submission
    //     alert('Form submitted and changes committed');
    //     // Place your AJAX call or form submission logic here
    // });
});




function form2json(form) {

    //var form = document.getElementById(formId);
    var formData = new FormData(form);

    var object = {};
    formData.forEach(function(value, key){
        object[key] = value;
    });

    var json = JSON.stringify(object);

    return json;
}

function sendForm(form) {
    
    return fetch(form.action, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: form2json(form)
    });

}

function checkRequired(form) {
    var requiredFields = form.querySelectorAll('input[required], textarea[required], select[required]');

    for (let field of requiredFields) {
        if (!field.value.trim()) {
            return false; // Return false as soon as an empty required field is found
        }
    }

    return true; // Return true if all required fields are filled
}


function submitForm(formID) {

    form = document.getElementById(formID)

    if (!checkRequired(form)) {
        // One could add animation here
        return;
    }

    sendForm(form)
        .then(response => {
            if (response.redirected) {
                window.location.href = response.url; // Redirect to the new URL
            } else {
                return response.json(); // Process the response as JSON
            }
        })
        .then(data => {
            if (data) {
                console.log('Success:', data);
                // Handle success response
            }
        })
        .catch((error) => {
            console.error('Error:', error);
            // Handle errors
        });

}


function submitFormsReload(formIds) {
    var formPromises = formIds.map(formId => {
        var form = document.getElementById(formId);
        return sendForm(form);
    });

    Promise.all(formPromises)
        .then(responses => Promise.all(responses.map(response => response.json())))
        .then(data => {
            console.log('All forms submitted successfully', data);
            window.location.reload(true); // Reload the page after all forms are submitted
        })
        .catch(error => {
            console.error('Error submitting forms:', error);
        });
}








