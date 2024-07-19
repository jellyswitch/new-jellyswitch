import { Controller } from "@hotwired/stimulus"
import "fullcalendar"

export default class extends Controller {
  connect() {
    this.today = $('input[name="date"]').val();

    this.initializeCalendar();

    this.handleDurationChange();
    this.handleRoomSelectionChange();
    this.handleFormSubmission();
    this.handleDayNightSelection();
    this.handleModalClose();

    this.handleReserveNowFlow();

    this.USDollar = new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    });
    this.reservationPrice = 0;
  }

  initializeCalendar() {
    $('#reservation-fullcalendar').fullCalendar({
      themeSystem: 'bootstrap4',
      businessHours: false,
      defaultView: 'month',
      showNonCurrentDates: false,
      header: {
        left: 'title',
        right: 'today prev,next'
      },
      dayClick: this.handleDayClick.bind(this),
    });

    setTimeout(function () {
      window.dispatchEvent(new Event('resize'));
    }, 100);
  }

  handleReserveNowFlow() {
    const isReserveNow = $('input[name="date"]').data('reserve-now');
    const currentDate = $('input[name="date"]').val();
    const availableTimeSlot = $("input[name='time']").val();
    const dayOrNight = $('input[name="day-light-options"]:checked').val();

    if (isReserveNow && currentDate && dayOrNight) {
      this.prefillReservationForm(currentDate, availableTimeSlot, dayOrNight);
    }
  }

  handleDurationChange() {
    $('#duration-slots-container .duration-slot').on('click', (event) => {
      const duration = $(event.target).data('duration');
      $('.duration-slot').removeClass('selected-time');
      $(event.target).addClass('selected-time');
      $('input[name="duration"]').val(duration);
      this.fetchAvailableRooms();
    });
  }

  handleRoomSelectionChange() {
    $('#rooms-select').on('change', () => {
      const roomId = $('#rooms-select').val();
      const duration = $('input[name="duration"]').val();
      const date = $('input[name="date"]').val();
      if (roomId && date && duration) {
        this.fetchRoomDetails(roomId, date, duration);
        $("#add-reservation button[type='submit']").removeAttr("disabled");
      }
    });
  }

  handleFormSubmission() {
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

      const amenityIds = [];
      $('.amenity-checkbox:checked').each(function () {
        amenityIds.push($(this).val());
      });

      this.createReservation({ room_id: roomId, date, time, duration, day_or_night: dayOrNight, amenity_ids: amenityIds });
    });
  }

  handleDayClick(date, event) {
    const formattedDate = date.format('YYYY-MM-DD');

    const hasFcPastClass = $(`td.fc-day[data-date="${formattedDate}"]`).hasClass('fc-past')
    const beforeToday = moment(this.today).isAfter(date)

    if (hasFcPastClass && beforeToday) return;

    this.highlightSelectedDate(formattedDate);
    const displayDate = date.format('MMMM D, YYYY');
    this.updateDateDisplay(displayDate);
    this.setInputDate(formattedDate);
    this.showEventModal();

    const dayOrNight = $('input[name="day-light-options"]:checked').val();
    this.fetchAvailableTimeSlots(formattedDate, dayOrNight);
  }

  handleTimeSlotClick(element, time) {
    $('.time-slot').removeClass('selected-time');
    element.addClass('selected-time');
    $('input[name="time"]').val(time);
    $('.duration-group').removeClass('d-none');
    this.fetchAvailableRooms();
  }

  handleDayNightSelection() {
    $('input[name="day-light-options"]').on('change', () => {
      const selectedOption = $('input[name="day-light-options"]:checked').val();
      const date = $('input[name="date"]').val();
      if (date) {
        this.fetchAvailableTimeSlots(date, selectedOption);
      }
    });
  }

  handleModalClose() {
    $('#modal-view-event-add').on('hidden.bs.modal', () => {
      this.clearSelections();
    });
  }

  // AJAX Functions
  fetchRoomDetails(roomId, date, duration) {
    $.ajax({
      url: '/reservations/room_price_and_details',
      method: 'GET',
      data: { room_id: roomId, date: date, duration: duration },
      success: (room) => {
        this.displayRoomDetails(room);
        this.reservationPrice = room.should_charge ? room.reservation_price : 0
      },
      error: (xhr, status, error) => {
        console.error('Error fetching room details:', error);
      }
    });
  }

  fetchAvailableTimeSlots(date, dayOrNight, callback = null) {
    $.ajax({
      url: '/reservations/available_time_slots',
      method: 'GET',
      data: { day: date, day_or_night: dayOrNight },
      success: (response) => {
        this.renderTimeSlots(response);
        callback && callback();
      },
      error: (xhr, status, error) => {
        console.error('Error fetching time slots:', error);
      }
    });
  }

  fetchAvailableRooms() {
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
        this.hideAmenities();

        $(".available-room-group").removeClass('d-none');
        $(".room-details").addClass('d-none');
        $(".price-container").addClass('d-none');
        this.renderAvailableRooms(response);
      },
      error: (xhr, status, error) => {
        console.error('Error fetching available rooms:', error);
      }
    });
  }

  createReservation({ room_id, date, time, duration, day_or_night, amenity_ids }) {
    $.ajax({
      url: '/reservations',
      method: 'POST',
      data: {
        room_id, date, time, duration, day_or_night, amenity_ids
      },
      error: (xhr, status, error) => {
        console.error('Error creating reservation:', error);
        alert('An error occurred while creating the reservation. Please try again.');
      }
    });
  }

  // Utility Functions
  prefillReservationForm(date, time, dayOrNight) {
    const dayClickDate = moment(date).startOf('day');

    this.handleDayClick(dayClickDate);

    $(`input[name="day-light-options"][value="${dayOrNight}"]`).prop('checked', true);

    this.fetchAvailableTimeSlots(date, dayOrNight, () => {
      time && $(`.time-slot:contains("${time}")`).click();
    });
  }

  highlightSelectedDate(date) {
    $('.selected-date').removeClass('selected-date');
    $(`td.fc-day[data-date="${date}"]`).addClass('selected-date');
    $(`td.fc-day-top[data-date="${date}"]`).addClass('selected-date');
  }

  updateDateDisplay(date) {
    $('.date-value').text(date);
  }

  setInputDate(date) {
    $('.reservation-date-input').val(date);
  }

  showEventModal() {
    $('#modal-view-event-add').modal();
  }

  clearSelections() {
    $('.time-slot').removeClass('selected-time');
    $('input[name="time"]').val('');

    $('.duration-group').addClass('d-none');
    $('.available-room-group').addClass('d-none');

    $('.duration-slot').removeClass('selected-time');
    $('input[name="duration"]').val('');

    $('#day-radio').prop('checked', true);

    $("#add-reservation button[type='submit']").attr("disabled", true);
  }

  handleFormState() {
    const roomId = $('select[name="room_id"]').val();
    const date = $('input[name="date"]').val();
    const time = $('input[name="time"]').val();
    const duration = $('input[name="duration"]').val();

    if (roomId && date && time && duration) {
      $("#add-reservation button[type='submit']").removeAttr("disabled");
    } else {
      $("#add-reservation button[type='submit']").attr("disabled", true);
    }
  }

  // Rendering Functions
  renderTimeSlots(timeSlots) {
    const timeSlotsContainer = $('#time-slots-container');
    timeSlotsContainer.empty();

    if (timeSlots.length === 0) {
      timeSlotsContainer.append('<p>No available time slots.</p>');
      return;
    }

    timeSlots.forEach(slot => {
      const timeSlotElement = $(`<div class="time-slot">${slot}</div>`);
      timeSlotElement.on('click', () => this.handleTimeSlotClick(timeSlotElement, slot));
      timeSlotsContainer.append(timeSlotElement);
    });
  }

  renderAvailableRooms(rooms) {
    const roomsSelect = $('#rooms-select');
    roomsSelect.empty();
    this.handleFormState();

    // Add the default option
    roomsSelect.append('<option value="" disabled selected>Select a room</option>');

    if (rooms.length === 0) {
      return;
    }

    rooms.forEach(room => {
      const optionElement = $(`<option value="${room.id}">${room.name}</option>`);
      roomsSelect.append(optionElement);
    });
  }

  hideAmenities() {
    $('.amenities-container').addClass('d-none');
  }

  displayAmenities(amenities, isMembership) {
    const amenitiesContainer = $('.amenities-container');
    const amenitiesList = $('.amenities-list');
    amenitiesList.empty();

    if (amenities.length === 0) {
      this.hideAmenities();
      return;
    }

    amenities.forEach((amenity, index) => {
      const displayPrice = isMembership ? amenity.membership_price : amenity.price;

      const amenityHtml = `
        <div class="col-12 col-md-6">
          <div class="form-check">
            <input class="form-check-input amenity-checkbox" type="checkbox" value="${amenity.id}" id="amenity-${amenity.id}" data-price="${displayPrice}">
            <label class="form-check-label amenity-item" for="amenity-${amenity.id}">
              ${amenity.name} - $${displayPrice}
            </label>
          </div>
        </div>
      `;
      amenitiesList.append(amenityHtml);
    });

    amenitiesContainer.removeClass('d-none');

    this.setupAmenityCheckboxHandlers();
  }

  displayRoomDetails(room) {
    const should_charge = room.should_charge && room.hourly_price != 0

    const hourlyPriceText = should_charge ? this.USDollar.format(room.hourly_price) : "Free";
    const reservationPriceText = this.USDollar.format(room.reservation_price);

    $('.room-details .hourly-price .details-value').text(hourlyPriceText);
    $('.room-details .room-capacity .details-value').text(room.capacity);

    let amenities = [];

    if (amenities.length > 0) {
      $('.room-details .room-amenities').show();
      $('.room-details .room-amenities .details-value').text(amenities.join(", "));
    } else {
      $('.room-details .room-amenities').hide();
    }

    if (should_charge) {
      $('.price-container .price-value').text(reservationPriceText);
      $('.price-container').removeClass('d-none');
    } else {
      $('.price-container').addClass('d-none');
    }

    $('.room-details').removeClass('d-none');

    const isMembership = !should_charge;
    this.displayAmenities(room.amenities, isMembership);
  }

  updateTotalPrice(price, isAdding) {
    if (isAdding) {
      this.reservationPrice += price;
    } else {
      this.reservationPrice -= price;
    }

    const isHidden = this.reservationPrice === 0;

    $('.price-container').toggleClass('d-none', isHidden);
    $('.price-container .price-value').text(this.USDollar.format(this.reservationPrice));
  }

  setupAmenityCheckboxHandlers() {
    $('.amenity-checkbox').off('change').on('change', (event) => {
      const checkbox = $(event.target);
      const price = parseFloat(checkbox.data('price'));
      this.updateTotalPrice(price, checkbox.is(':checked'));
    });
  }
}
