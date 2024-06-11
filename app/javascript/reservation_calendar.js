$(document).ready(function () {
    initializeCalendar();
    initializeDatepicker();
    handleDurationChange();
    handleRoomSelectionChange();
    handleFormSubmission();
    handleDayNightSelection();
});

// Initialization Functions
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

const initializeDatepicker = () => {
    $('.reservation-date-input').datepicker({
        timepicker: false,
        language: 'en',
        dateFormat: 'yyyy-mm-dd'
    });
};

// Event Handlers
const handleDurationChange = () => {
    $('#duration-slots-container .duration-slot').on('click', function () {
        const duration = $(this).data('duration');
        $('.duration-slot').removeClass('selected-time');
        $(this).addClass('selected-time');
        $('input[name="duration"]').val(duration);
        fetchAvailableRooms();
    });
};

const handleRoomSelectionChange = () => {
    $('#rooms-select').on('change', function () {
        const roomId = $(this).val();
        const duration = $('input[name="duration"]').val();
        const date = $('input[name="date"]').val();
        if (roomId && date && duration) {
            fetchRoomDetails(roomId, date, duration);
            $("#add-reservation button[type='submit']").removeAttr("disabled");
        }
    });
};

const handleFormSubmission = () => {
    $('#add-reservation').on('submit', (event) => {
        event.preventDefault();

        const roomId = $('select[name="room_id"]').val();
        const date = $('input[name="date"]').val();
        const time = $('input[name="time"]').val();
        const dayOrNight = $('input[name="day-light-options"]:checked').val();
        const duration = $('input[name="duration"]').val();

        if (!roomId || !date || !time || !duration) {
            alert('Please select a room, date, time, and duration.');
            return;
        }

        createReservation({ room_id: roomId, date, time, duration, day_or_night: dayOrNight });
    });
};

const handleDayClick = (date, event) => {
    const formattedDate = date.format('YYYY-MM-DD');
    highlightSelectedDate(formattedDate);
    const displayDate = date.format('MMMM D, YYYY');
    updateDateDisplay(displayDate);
    setDatepickerDate(date._d);
    showEventModal();
    clearSelections();

    const dayOrNight = $('input[name="day-light-options"]:checked').val();
    fetchAvailableTimeSlots(formattedDate, dayOrNight);
};

const handleTimeSlotClick = (element, time) => {
    $('.time-slot').removeClass('selected-time');
    element.addClass('selected-time');
    $('input[name="time"]').val(time);
    $('.duration-group').removeClass('d-none');
    fetchAvailableRooms();
};

const handleDayNightSelection = () => {
    $('input[name="day-light-options"]').on('change', function () {
        const selectedOption = $(this).val();
        const date = $('input[name="date"]').val();
        if (date) {
            fetchAvailableTimeSlots(date, selectedOption);
        }
    });
};

// AJAX Functions
const fetchRoomDetails = (roomId, date, duration) => {
    $.ajax({
        url: '/reservations/room_price_and_details',
        method: 'GET',
        data: { room_id: roomId, date: date, duration: duration },
        success: (room) => {
            displayRoomDetails(room);
        },
        error: (xhr, status, error) => {
            console.error('Error fetching room details:', error);
        }
    });
};

const fetchAvailableTimeSlots = (date, dayOrNight) => {
    $.ajax({
        url: '/reservations/available_time_slots',
        method: 'GET',
        data: { day: date, day_or_night: dayOrNight },
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
    const dayOrNight = $('input[name="day-light-options"]:checked').val();

    if (!date || !time || !duration) return;

    $.ajax({
        url: '/reservations/available_rooms',
        method: 'GET',
        data: { date: date, time: time, duration: duration, day_or_night: dayOrNight },
        success: (response) => {
            $(".available-room-group").removeClass('d-none');
            $(".room-details").addClass('d-none');
            $(".price-container").addClass('d-none');
            renderAvailableRooms(response);
        },
        error: (xhr, status, error) => {
            console.error('Error fetching available rooms:', error);
        }
    });
};

const createReservation = ({ room_id, date, time, duration, day_or_night }) => {
    $.ajax({
        url: '/reservations',
        method: 'POST',
        data: {
            room_id, date, time, duration, day_or_night
        },
        error: (xhr, status, error) => {
            console.error('Error creating reservation:', error);
            alert('An error occurred while creating the reservation. Please try again.');
        }
    });
};

// Utility Functions
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

const clearSelections = () => {
    $('.time-slot').removeClass('selected-time');
    $('input[name="time"]').val('');

    $('.duration-group').addClass('d-none');
    $('.available-room-group').addClass('d-none');

    $('.duration-slot').removeClass('selected-time');
    $('input[name="duration"]').val('');

    $('#day-radio').prop('checked', true);

    $("#add-reservation button[type='submit']").attr("disabled", true);
};

const handleFormState = () => {
    const roomId = $('select[name="room_id"]').val();
    const date = $('input[name="date"]').val();
    const time = $('input[name="time"]').val();
    const duration = $('input[name="duration"]').val();

    if (roomId && date && time && duration) {
        $("#add-reservation button[type='submit']").removeAttr("disabled");
    } else {
        $("#add-reservation button[type='submit']").attr("disabled", true);
    }
};

// Rendering Functions
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

const renderAvailableRooms = (rooms) => {
    const roomsSelect = $('#rooms-select');
    roomsSelect.empty();
    handleFormState();

    // Add the default option
    roomsSelect.append('<option value="" disabled selected>Select a room</option>');

    if (rooms.length === 0) {
        return;
    }

    rooms.forEach(room => {
        const optionElement = $(`<option value="${room.id}">${room.name}</option>`);
        roomsSelect.append(optionElement);
    });
};

const displayRoomDetails = (room) => {
    const hourlyPriceText = (!room.should_charge || room.hourly_price == "$0.00") ? "Free" : room.hourly_price;
    const reservationPriceText = room.reservation_price;

    $('.room-details .hourly-price .details-value').text(hourlyPriceText);
    $('.room-details .room-capacity .details-value').text(room.capacity);

    let amenities = [];
    if (room.av) amenities.push("AV Equipment");
    if (room.whiteboard) amenities.push("Whiteboard");

    if (amenities.length > 0) {
        $('.room-details .room-amenities').show();
        $('.room-details .room-amenities .details-value').text(amenities.join(", "));
    } else {
        $('.room-details .room-amenities').hide();
    }

    if (room.should_charge) {
        $('.price-container .price-value').text(reservationPriceText);
        $('.price-container').removeClass('d-none');
    } else {
        $('.price-container').addClass('d-none');
    }

    $('.room-details').removeClass('d-none');
};