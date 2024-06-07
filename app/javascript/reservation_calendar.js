$(document).ready(function () {
    initializeCalendar();
    initializeDatepicker();
    handleFormSubmission();

    handleDurationChange();
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

    clearSelections();

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

const fetchAvailableRooms = () => {
    const date = $('input[name="date"]').val();
    const time = $('input[name="time"]').val();
    const duration = $('input[name="duration"]').val();

    if (!date || !time || !duration) return;

    $.ajax({
        url: '/reservations/available_rooms',
        method: 'GET',
        data: { date: date, time: time, duration: duration },
        success: (response) => {
            renderAvailableRooms(response);
        },
        error: (xhr, status, error) => {
            console.error('Error fetching available rooms:', error);
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
    $('.duration-group').removeClass('d-none');

    fetchAvailableRooms();
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
        dateFormat: 'yyyy-mm-dd'
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

const handleDurationChange = () => {
    $('#duration-slots-container .duration-slot').on('click', function () {
        const duration = $(this).data('duration');
        $('.duration-slot').removeClass('selected-time');
        $(this).addClass('selected-time');
        $('input[name="duration"]').val(duration);
        $(".available-room-group").removeClass('d-none');

        fetchAvailableRooms();
    });
};

const renderAvailableRooms = (rooms) => {
    const roomsSelect = $('#rooms-select');
    roomsSelect.empty();

    if (rooms.length === 0) {
        roomsSelect.append('<option>No available rooms</option>');
        return;
    }

    rooms.forEach(room => {
        const optionElement = $(`<option value="${room.id}">${room.name}</option>`);
        roomsSelect.append(optionElement);
    });
};

const clearSelections = () => {
    $('.time-slot').removeClass('selected-time');
    $('input[name="time"]').val('');

    $('.duration-group').addClass('d-none');
    $('.available-room-group').addClass('d-none');

    $('.duration-slot').removeClass('selected-time');
    $('input[name="duration"]').val('');
};