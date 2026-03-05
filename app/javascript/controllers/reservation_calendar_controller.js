import { Controller } from "@hotwired/stimulus";
import "fullcalendar";
import moment from "moment"
import "moment-timezone"

export default class extends Controller {
  connect() {
    this.today = $('input[name="date"]').val();
    this.selectedRoomId = null;
    this.reservationCounts = {};
    this.isManager = this.element.dataset.isManager === "true";
    this.needsBilling = false;
    this.stripe = null;
    this.card = null;

    this.initializeCalendar();
    this.initializeRoomFilter();

    this.handleDurationChange();
    this.handleRoomSelectionChange();
    this.handleFormSubmission();
    this.handleDayNightSelection();
    this.handleModalClose();
    this.handleReserveNowFlow();
    this.handleReservationListToggle();

    this.USDollar = new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
    });
    this.reservationPrice = 0;
  }

  initializeCalendar() {
    $("#reservation-fullcalendar").fullCalendar({
      themeSystem: "bootstrap4",
      businessHours: false,
      defaultView: "month",
      showNonCurrentDates: false,
      header: {
        left: "title",
        right: "today prev,next",
      },
      dayClick: this.handleDayClick.bind(this),
      eventClick: (event) => {
        this.handleDayClick(moment(event.id));
      },
      events: (start, end, timezone, callback) => {
        $.ajax({
          url: "/reservations/daily_counts",
          method: "GET",
          data: {
            start_date: start.format("YYYY-MM-DD"),
            end_date: end.format("YYYY-MM-DD"),
            room_id: this.selectedRoomId,
          },
          success: (response) => {
            const events = Object.entries(response)
              .filter(([date, count]) => count > 0)
              .map(([date, count]) => ({
                id: date,
                title: count === 1 ? "1 reservation" : `${count} reservations`,
                start: date,
                allDay: true,
                className: 'reservation-count-event'
              }));
            callback(events);
          },
          error: (xhr, status, error) => {
            console.error("Error fetching reservation counts:", error);
            callback([]);
          }
        });
      },
      eventRender: function(event, element) {
        element.find('.fc-content').html(event.title);
      }
    });

    setTimeout(() => window.dispatchEvent(new Event("resize")), 100);
  }

  handleReserveNowFlow() {
    const isReserveNow = $('input[name="date"]').data("reserve-now");
    const currentDate = $('input[name="date"]').val();
    const availableTimeSlot = $("input[name='time']").val();
    const dayOrNight = $('input[name="day-light-options"]:checked').val();

    if (isReserveNow && currentDate && dayOrNight) {
      this.prefillReservationForm(currentDate, availableTimeSlot, dayOrNight);
    }
  }

  initializeRoomFilter() {
    $("#room-filter").on("change", (event) => {
      this.selectedRoomId = event.target.value;
      this.updateCalendarWithReservations();
    });
  }

  async fetchReservationCounts(start, end, callback) {
    try {
      const response = await $.ajax({
        url: "/reservations/daily_counts",
        method: "GET",
        data: {
          start_date: start.format("YYYY-MM-DD"),
          end_date: end.format("YYYY-MM-DD"),
          room_id: this.selectedRoomId,
        },
      });

      // Transform the counts into fullCalendar events
      const events = Object.entries(response).map(([date, count]) => ({
        id: date,
        title: count === 1 ? "1 reservation" : `${count} reservations`,
        start: date,
        allDay: true,
        className: 'reservation-count-event'
      })).filter(event => event.count > 0);

      callback(events);
    } catch (error) {
      console.error("Error fetching reservation counts:", error);
      callback([]);
    }
  }

  async fetchDayReservations(date) {
    try {
      const response = await $.ajax({
        url: "/reservations/daily_details",
        method: "GET",
        data: { date: date },
      });
      this.renderReservationsList(response);
    } catch (error) {
      console.error("Error fetching day reservations:", error);
    }
  }

  renderReservationsList(reservations) {
    const container = $(".reservations-list");
    container.empty();
    const locationTimezone = this.element.dataset.locationTimezone;
    $(".reservation-count-badge").text(reservations.length);

    if (reservations.length === 0) {
      $(".existing-reservations").hide();
      container.append('<div class="no-reservations">No reservations for this day</div>');
      return;
    }
    $(".existing-reservations").show();

    // Sort reservations by datetime_in
    reservations.sort((a, b) => new Date(a.datetime_in) - new Date(b.datetime_in));

    reservations.forEach(reservation => {
      const startTime = moment.tz(reservation.datetime_in, locationTimezone);
      const endTime = moment.tz(reservation.datetime_in, locationTimezone)
        .add(reservation.minutes, 'minutes');

      const extraDetails = this.isManager ? `<span class="reservation-note">(${reservation.user_name}${reservation.note ? ': ' + reservation.note : ''})</span>` : '';

      const item = $(`
        <div class="reservation-item">
          ${this.formatTimeInTimezone(startTime)} - ${this.formatTimeInTimezone(endTime)} -
          <span class="room-name font-weight-bold">${reservation.room_name}</span>
          ${extraDetails}
        </div>
      `);
      container.append(item);
    });
  }

  formatTimeInTimezone(momentTime) {
    return momentTime.format('h:mm A');
  }

  formatTime(date) {
    return date.toLocaleTimeString('en-US', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    });
  }

  handleReservationListToggle() {
    $('.reservations-list-toggle').on('click', function() {
      $(this).toggleClass('collapsed');
      const icon = $(this).find('i.fas');
      icon.toggleClass('fa-chevron-right fa-chevron-down');
    });
  }

  updateCalendarWithReservations() {
    $("#reservation-fullcalendar").fullCalendar('refetchEvents');
  }

  handleDurationChange() {
    $("#duration-slots-container .duration-slot").on("click", (event) => {
      const duration = $(event.target).data("duration");
      $(".duration-slot").removeClass("selected-time");
      $(event.target).addClass("selected-time");
      $('input[name="duration"]').val(duration);
      this.fetchAvailableRooms();
    });
  }

  handleRoomSelectionChange() {
    $("#rooms-select").on("change", () => {
      const roomId = $("#rooms-select").val();
      const duration = $('input[name="duration"]').val();
      const date = $('input[name="date"]').val();
      if (roomId && date && duration) {
        this.fetchRoomDetails(roomId, date, duration);
        $("#add-reservation button[type='submit']").removeAttr("disabled");
      }
    });
  }

  handleFormSubmission() {
    $("#add-reservation").on("submit", (event) => {
      event.preventDefault();

      const roomId = $('select[name="room_id"]').val();
      const date = $('input[name="date"]').val();
      const time = $('input[name="time"]').val();
      const dayOrNight = $('input[name="day-light-options"]:checked').val();
      const duration = $('input[name="duration"]').val();
      const note = $("#reservation-note").val();

      if (!roomId || !date || !time || !duration) {
        alert("Please select a room, date, time, and duration.");
        return;
      }

      const amenityIds = [];
      $(".amenity-checkbox:checked").each(function () {
        amenityIds.push($(this).val());
      });

      this.createReservation({
        room_id: roomId,
        date,
        time,
        duration,
        day_or_night: dayOrNight,
        amenity_ids: amenityIds,
        note: note,
      });
    });
  }

  async handleDayClick(date, event) {
    const formattedDate = date.format("YYYY-MM-DD");

    const hasFcPastClass = $(
      `td.fc-day[data-date="${formattedDate}"]`
    ).hasClass("fc-past");
    const beforeToday = moment(this.today).isAfter(date);

    // if (hasFcPastClass && beforeToday) return;

    this.highlightSelectedDate(formattedDate);
    const displayDate = date.format("MMMM D, YYYY");
    this.updateDateDisplay(displayDate);
    this.setInputDate(formattedDate);
    await this.fetchDayReservations(formattedDate);
    this.showEventModal();

    const dayOrNight = $('input[name="day-light-options"]:checked').val();
    this.fetchAvailableTimeSlots(formattedDate, dayOrNight);
  }

  handleTimeSlotClick(element, time) {
    $(".time-slot").removeClass("selected-time");
    element.addClass("selected-time");
    $('input[name="time"]').val(time);
    $(".duration-group").removeClass("d-none");
    this.fetchAvailableRooms();
  }

  handleDayNightSelection() {
    $('input[name="day-light-options"]').on("change", () => {
      const selectedOption = $('input[name="day-light-options"]:checked').val();
      const date = $('input[name="date"]').val();
      if (date) {
        this.fetchAvailableTimeSlots(date, selectedOption);
      }
    });
  }

  handleModalClose() {
    $("#modal-view-event-add").on("hidden.bs.modal", () => {
      this.clearSelections();
    });
  }

  // AJAX Functions
  fetchRoomDetails(roomId, date, duration) {
    $.ajax({
      url: "/reservations/room_price_and_details",
      method: "GET",
      data: { room_id: roomId, date: date, duration: duration },
      success: (room) => {
        this.displayRoomDetails(room);
        this.reservationPrice = room.should_charge ? room.reservation_price : 0;
        this.checkNeedsBilling(date);
      },
      error: (xhr, status, error) => {
        console.error("Error fetching room details:", error);
      },
    });
  }

  checkNeedsBilling(date) {
    $.ajax({
      url: "/reservations/needs_billing",
      method: "GET",
      data: { date: date },
      success: (response) => {
        this.needsBilling = response.needs_billing;
        if (this.needsBilling) {
          this.showBillingSection();
        } else {
          this.hideBillingSection();
        }
      },
      error: (xhr, status, error) => {
        console.error("Error checking billing status:", error);
        this.needsBilling = false;
        this.hideBillingSection();
      },
    });
  }

  showBillingSection() {
    $(".billing-section").removeClass("d-none");
    if (!this.stripe) {
      this.stripe = Stripe(window.stripe_key);
      const elements = this.stripe.elements();
      this.card = elements.create("card", {});
      this.card.mount("#card-element");
      this.card.addEventListener("change", (event) => {
        const displayError = document.getElementById("card-errors");
        displayError.textContent = event.error ? event.error.message : "";
      });
    }
  }

  hideBillingSection() {
    $(".billing-section").addClass("d-none");
  }

  fetchAvailableTimeSlots(date, dayOrNight, callback = null) {
    $.ajax({
      url: "/reservations/available_time_slots",
      method: "GET",
      data: { day: date, day_or_night: dayOrNight },
      success: (response) => {
        this.renderTimeSlots(response);
        callback && callback();
      },
      error: (xhr, status, error) => {
        console.error("Error fetching time slots:", error);
      },
    });
  }

  fetchAvailableRooms() {
    const date = $('input[name="date"]').val();
    const time = $('input[name="time"]').val();
    const duration = $('input[name="duration"]').val();
    const dayOrNight = $('input[name="day-light-options"]:checked').val();

    if (!date || !time || !duration) return;

    $.ajax({
      url: "/reservations/available_rooms",
      method: "GET",
      data: {
        date: date,
        time: time,
        duration: duration,
        day_or_night: dayOrNight,
      },
      success: (response) => {
        this.hideAmenities();

        $(".available-room-group").removeClass("d-none");
        $(".room-details").addClass("d-none");
        $(".price-container").addClass("d-none");
        this.renderAvailableRooms(response);
      },
      error: (xhr, status, error) => {
        console.error("Error fetching available rooms:", error);
      },
    });
  }

  async createReservation({
    room_id,
    date,
    time,
    duration,
    day_or_night,
    amenity_ids,
    note,
  }) {
    const data = { room_id, date, time, duration, day_or_night, amenity_ids, note };

    if (this.needsBilling && this.stripe && this.card) {
      const submitBtn = $("#add-reservation button[type='submit']");
      submitBtn.attr("disabled", true);

      const result = await this.stripe.createToken(this.card);
      if (result.error) {
        const errorElement = document.getElementById("card-errors");
        errorElement.textContent = result.error.message;
        submitBtn.removeAttr("disabled");
        return;
      }
      data.stripeToken = result.token.id;
    }

    $.ajax({
      url: "/reservations",
      method: "POST",
      data: data,
      error: (xhr, status, error) => {
        console.error("Error creating reservation:", error);
        alert(
          "An error occurred while creating the reservation. Please try again."
        );
      },
    });
  }

  // Utility Functions
  prefillReservationForm(date, time, dayOrNight) {
    const dayClickDate = moment(date).startOf("day");

    this.handleDayClick(dayClickDate);

    $(`input[name="day-light-options"][value="${dayOrNight}"]`).prop(
      "checked",
      true
    );

    this.fetchAvailableTimeSlots(date, dayOrNight, () => {
      time && $(`.time-slot:contains("${time}")`).click();
    });
  }

  highlightSelectedDate(date) {
    $(".selected-date").removeClass("selected-date");
    $(`td.fc-day[data-date="${date}"]`).addClass("selected-date");
    $(`td.fc-day-top[data-date="${date}"]`).addClass("selected-date");
  }

  updateDateDisplay(date) {
    $(".date-value").text(date);
  }

  setInputDate(date) {
    $(".reservation-date-input").val(date);
  }

  showEventModal() {
    $("#modal-view-event-add").modal();
  }

  clearSelections() {
    $(".time-slot").removeClass("selected-time");
    $('input[name="time"]').val("");

    $(".duration-group").addClass("d-none");
    $(".available-room-group").addClass("d-none");

    $(".duration-slot").removeClass("selected-time");
    $('input[name="duration"]').val("");

    $("#day-radio").prop("checked", true);

    $("#add-reservation button[type='submit']").attr("disabled", true);

    $(".note-container").addClass("d-none");
    $("#reservation-note").val("");

    this.needsBilling = false;
    this.hideBillingSection();
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
    const timeSlotsContainer = $("#time-slots-container");
    timeSlotsContainer.empty();

    if (timeSlots.length === 0) {
      timeSlotsContainer.append("<p>No available time slots.</p>");
      return;
    }

    timeSlots.forEach((slot) => {
      const timeSlotElement = $(`<div class="time-slot">${slot}</div>`);
      timeSlotElement.on("click", () =>
        this.handleTimeSlotClick(timeSlotElement, slot)
      );
      timeSlotsContainer.append(timeSlotElement);
    });
  }

  renderAvailableRooms(rooms) {
    const roomsSelect = $("#rooms-select");
    roomsSelect.empty();
    this.handleFormState();

    // Add the default option
    roomsSelect.append(
      '<option value="" disabled selected>Select a room</option>'
    );

    if (rooms.length === 0) {
      return;
    }

    rooms.forEach((room) => {
      const optionElement = $(
        `<option value="${room.id}">${room.name}</option>`
      );
      roomsSelect.append(optionElement);
    });
  }

  hideAmenities() {
    $(".amenities-container").addClass("d-none");
  }

  displayAmenities(amenities, isMembership) {
    const amenitiesContainer = $(".amenities-container");
    const amenitiesList = $(".amenities-list");
    amenitiesList.empty();

    if (amenities.length === 0) {
      this.hideAmenities();
      return;
    }

    amenities.forEach((amenity, index) => {
      const displayPrice = isMembership
        ? amenity.membership_price
        : amenity.price;

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

    amenitiesContainer.removeClass("d-none");

    this.setupAmenityCheckboxHandlers();
  }

  displayRoomDetails(room) {
    const should_charge = room.should_charge && room.hourly_price != 0;

    const hourlyPriceText = should_charge
      ? this.USDollar.format(room.hourly_price)
      : "Free";
    const reservationPriceText = this.USDollar.format(room.reservation_price);

    $(".room-details .hourly-price .details-value").text(hourlyPriceText);
    $(".room-details .room-capacity .details-value").text(room.capacity);

    let amenities = [];

    if (amenities.length > 0) {
      $(".room-details .room-amenities").show();
      $(".room-details .room-amenities .details-value").text(
        amenities.join(", ")
      );
    } else {
      $(".room-details .room-amenities").hide();
    }

    if (should_charge) {
      $(".price-container .price-value").text(reservationPriceText);
      $(".price-container").removeClass("d-none");
    } else {
      $(".price-container").addClass("d-none");
    }

    $(".room-details").removeClass("d-none");
    $(".note-container").removeClass("d-none");

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

    $(".price-container").toggleClass("d-none", isHidden);
    $(".price-container .price-value").text(
      this.USDollar.format(this.reservationPrice)
    );
  }

  setupAmenityCheckboxHandlers() {
    $(".amenity-checkbox")
      .off("change")
      .on("change", (event) => {
        const checkbox = $(event.target);
        const price = parseFloat(checkbox.data("price"));
        this.updateTotalPrice(price, checkbox.is(":checked"));
      });
  }
}
