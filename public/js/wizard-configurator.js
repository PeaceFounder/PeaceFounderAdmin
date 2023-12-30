function checkPasswordStrength() {
    var strengthBar = document.getElementById('pwindicator');
    var strengthText = strengthBar.children[0];

    var password = document.getElementById('password').value;
    var strength = 0;

    // Check for various conditions and increment strength
    if (password.match(/[a-z]+/)) {
        strength++;
    }
    if (password.match(/[A-Z]+/)) {
        strength++;
    }
    if (password.match(/[0-9]+/)) {
        strength++;
    }
    if (password.match(/[$@#&!]+/)) {
        strength++;
    }

    switch (strength) {
    case 0:
        strengthText.innerHTML = '';
        return false;
    case 1:
        strengthBar.className = 'pw-very-weak';
        strengthText.innerHTML = 'Very Weak <i class="zmdi zmdi-info"></i>';
        return false;
    case 2:
        strengthBar.className = 'pw-mediocre';
        strengthText.innerHTML = 'Moderate <i class="zmdi zmdi-info"></i>';
        return false;
    case 3:
    case 4:
        strengthBar.className = 'pw-very-strong';
        strengthText.innerHTML = 'Strong <i class="zmdi zmdi-info"></i>';
        return true;
    }

}


function checkPasswordEquality() {
    
    var password = document.getElementById('password').value;
    var password2 = document.getElementById('password2').value;
    

    var strengthBar = document.getElementById('pwindicator2');
    var strengthText = strengthBar.children[0];    

    if (password == password2) {
        strengthBar.className = 'pw-very-strong';
        strengthText.innerHTML = 'Correct <i class="zmdi zmdi-info"></i>';

        return true;
    } else {
        strengthBar.className = 'pw-very-weak';
        strengthText.innerHTML = 'Does Not Match <i class="zmdi zmdi-info"></i>';

        return false;
    }
        
}


function form2json(formId) {

    var form = document.getElementById(formId);
    var formData = new FormData(form);

    var object = {};
    formData.forEach(function(value, key){
        object[key] = value;
    });

    var json = JSON.stringify(object);

    return json;
}


function postData(url, json) {
    return fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: json
    });
        //.then(response => response.json());
}


async function submitForm() {

    //var form = document.getElementById("configuration");

    let hasError = !checkPasswordStrength() || !checkPasswordEquality()

    if (hasError) {

        let btn = document.getElementById('submitBtn');
        btn.classList.add('shake');

        // Optionally, remove the class after the animation ends
        btn.addEventListener('animationend', () => {
            btn.classList.remove('shake');
        });
    } else {

        json = form2json("configuration");
        
        const response = await postData('configurator', json)
            
        if (response.ok) {
            window.location.assign("setup-summary");            
        } else {
            console.log(`Error: HTTP error! Status: ${response.status}`)
        };
            
        // postData('configurator', json)
        //     .then(data => console.log(data))
        //     .catch(error => console.error('Error:', error));
    }
}
