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
    // Select all text inputs and checkboxes with the 'data-original-value' or 'data-original-checked' attributes
    var elements = document.querySelectorAll('input[data-original-value], input[type="checkbox"][data-original-checked]');

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
