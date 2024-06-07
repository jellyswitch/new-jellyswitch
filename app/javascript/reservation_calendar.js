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

    fetchAvailableTimeSlots(formattedDate);
};

const fetchAvailableTimeSlots = (date) => {
    $.ajax({
        url: '/reservations/available_time_slots',
        method: 'GET',
        data: { day: date },
        success: (response) => {
            renderTimeSlots(response);
        },
        error: (xhr, status, error) => {
            console.error('Error fetching time slots:', error);
        }
    });
};

const renderTimeSlots = (timeSlots) => {
    const timeSlotsContainer = $('#time-slots-container');
    timeSlotsContainer.empty();

    if (timeSlots.length === 0) {
        timeSlotsContainer.append('<p>No available time slots.</p>');
        return;
    }

    timeSlots.forEach(slot => {
        const timeSlotElement = $(`<div class="time-slot">${slot}</div>`);
        timeSlotElement.on('click', () => handleTimeSlotClick(timeSlotElement, slot));
        timeSlotsContainer.append(timeSlotElement);
    });
};

const handleTimeSlotClick = (element, time) => {
    $('.time-slot').removeClass('selected-time');

    element.addClass('selected-time');

    $('input[name="time"]').val(time);
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

