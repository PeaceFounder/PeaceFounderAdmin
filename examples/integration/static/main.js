function form2json(form) {

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

function submitForm(formID) {

    form = document.getElementById(formID)

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
