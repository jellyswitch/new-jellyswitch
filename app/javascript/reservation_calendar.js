$(document).ready(function () {
    initializeCalendar();
    initializeDatepicker();
    handleFormSubmission();
});

const initializeCalendar = () => {
    $('#reservation-fullcalendar').fullCalendar({
        themeSystem: 'bootstrap4',
        businessHours: false,
        defaultView: 'month',
        header: {
            left: 'title',
            right: 'today prev,next'
        },
        dayClick: handleDayClick,
    });
};

const handleDayClick = (date, event) => {
    const currentDate = moment();
    if (date.isBefore(currentDate, 'day')) {
        return;
    }

    const formattedDate = date.format('YYYY-MM-DD');
    highlightSelectedDate(formattedDate);

    const displayDate = date.format('MMMM D, YYYY');
    updateDateDisplay(displayDate);

    setDatepickerDate(date._d);
    showEventModal();
};

const highlightSelectedDate = (date) => {
    $('.selected-date').removeClass('selected-date');
    $(`td.fc-day[data-date="${date}"]`).addClass('selected-date');
    $(`td.fc-day-top[data-date="${date}"]`).addClass('selected-date');
};

const updateDateDisplay = (date) => {
    $('.date-value').text(date);
};

const setDatepickerDate = (date) => {
    const datepickerElement = $('.reservation-date-input').datepicker().data('datepicker');
    datepickerElement.selectDate(date);
};

const showEventModal = () => {
    $('#modal-view-event-add').modal();
};

const initializeDatepicker = () => {
    $('.reservation-date-input').datepicker({
        timepicker: false,
        language: 'en',
    });
};

const handleFormSubmission = () => {
    $('#add-reservation').on('submit', (event) => {
        event.preventDefault();

        const formData = $(event.currentTarget).serializeArray();
        console.log('Form Data Submitted:');
        formData.forEach(field => {
            console.log(`${field.name}: ${field.value}`);
        });

        alert("The form has been submitted!");
    });
};

