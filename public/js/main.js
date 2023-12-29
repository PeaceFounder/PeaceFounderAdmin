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




// $('#birthday').datepicker({
//     format: 'dd/mm/yyyy'
// });

// $('#birthday').datepicker({
//     dateFormat: 'dd/mm/yy'
// });
