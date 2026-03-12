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
    this.isModalOpen = false;
    this.pendingAjax = [];
    this._durationClickLock = false;
    this._timeSlotClickLock = false;

    this.initializeCalendar();
    this.initializeRoomFilter();

    this.handleDurationChange();
    this.handleRoomSelectionChange();
    this.handleFormSubmission();
    this.handleModalClose();
    this.handleReserveNowFlow();
    this.handleReservationListToggle();
    this.initializeBottomSheet();

    this.USDollar = new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
    });
    this.reservationPrice = 0;
  }

  disconnect() {
    // Clean up all event handlers when Stimulus disconnects
    $("#reservation-fullcalendar").off("click.mobiletap");
    $("#duration-slots-container").off("click.duration touchend.duration");
    $("#time-slots-container").off("click.timeslot touchend.timeslot");
    $("#rooms-select").off("change");
    $("#add-reservation").off("submit");
    $("#modal-view-event-add").off("hidden.bs.modal");
    $("#room-filter").off("change");
    $(".reservations-list-toggle").off("click");

    // Abort pending AJAX
    this.pendingAjax.forEach(xhr => {
      if (xhr && xhr.readyState !== 4) xhr.abort();
    });
    this.pendingAjax = [];

    // Force close modal and clean up backdrop
    if (this.isModalOpen) {
      $("#modal-view-event-add").modal("hide");
      $(".modal-backdrop").remove();
      $("body").removeClass("modal-open").css("padding-right", "");
    }
    this.isModalOpen = false;
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
        const eventDate = moment(event.id);
        // Block past date events too
        if (moment().startOf("day").isAfter(eventDate)) return;
        this.handleDayClick(eventDate);
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

    // On mobile, the content-skeleton layer covers the fc-bg layer and
    // blocks dayClick from firing on much of the cell. Attach a direct
    // tap handler on the entire calendar so ANY touch inside a date cell
    // triggers handleDayClick, making the full rectangle tappable.
    if (window.innerWidth <= 768) {
      this._mobileTapLock = false;
      $("#reservation-fullcalendar").on("click.mobiletap", ".fc-content-skeleton td, .fc-day-grid-event, .fc-day-number", (e) => {
        // Debounce to avoid double-fire with dayClick/eventClick
        if (this._mobileTapLock) return;
        this._mobileTapLock = true;
        setTimeout(() => { this._mobileTapLock = false; }, 500);

        // Walk up to find the column index, then look up the date from the bg row
        const td = $(e.target).closest("td");
        const row = td.closest(".fc-row");
        const colIndex = td.index();

        // The fc-bg table in the same row has td.fc-day elements with data-date
        const bgCell = row.find(".fc-bg td.fc-day").eq(colIndex);
        const dateStr = bgCell.data("date");
        if (!dateStr) return;

        const clickedDate = moment(dateStr);
        this.handleDayClick(clickedDate);
      });
    }
  }

  handleReserveNowFlow() {
    const isReserveNow = $('input[name="date"]').data("reserve-now");
    const currentDate = $('input[name="date"]').val();
    const availableTimeSlot = $("input[name='time']").val();

    if (isReserveNow && currentDate) {
      this.prefillReservationForm(currentDate, availableTimeSlot);
    }
  }

  initializeRoomFilter() {
    $("#room-filter").off("change").on("change", (event) => {
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
    $('.reservations-list-toggle').off('click').on('click', function() {
      $(this).toggleClass('collapsed');
      const icon = $(this).find('i.fas');
      icon.toggleClass('fa-chevron-right fa-chevron-down');
    });
  }

  updateCalendarWithReservations() {
    $("#reservation-fullcalendar").fullCalendar('refetchEvents');
  }

  handleDurationChange() {
    $("#duration-slots-container").off("click.duration touchend.duration");
    $("#duration-slots-container").on("click.duration touchend.duration", ".duration-slot", (event) => {
      event.preventDefault();
      event.stopPropagation();

      // Debounce guard: ignore rapid duplicate fires (touch + click)
      if (this._durationClickLock) return;
      this._durationClickLock = true;
      setTimeout(() => { this._durationClickLock = false; }, 400);

      const slot = $(event.currentTarget);
      const duration = slot.data("duration");

      // Remove selection from ALL duration slots, then select this one
      $("#duration-slots-container .duration-slot").removeClass("selected-time");
      slot.addClass("selected-time");
      $('input[name="duration"]').val(duration);
      this.hideOverageAlert();
      this.fetchAvailableRooms();

      // Auto-scroll to room selection
      setTimeout(() => {
        const roomGroup = document.querySelector(".available-room-group");
        if (roomGroup) {
          roomGroup.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      }, 300);
    });
  }

  handleRoomSelectionChange() {
    $("#rooms-select").off("change").on("change", () => {
      const roomId = $("#rooms-select").val();
      const duration = $('input[name="duration"]').val();
      const date = $('input[name="date"]').val();
      if (roomId && date && duration) {
        this.fetchRoomDetails(roomId, date, duration);
        $("#add-reservation button[type='submit']").removeAttr("disabled");

        // Auto-scroll to confirm button
        setTimeout(() => {
          const footer = document.querySelector(".modal-footer");
          if (footer) {
            footer.scrollIntoView({ behavior: "smooth", block: "center" });
          }
        }, 300);
      }
    });
  }

  handleFormSubmission() {
    $("#add-reservation").off("submit").on("submit", (event) => {
      event.preventDefault();

      const roomId = $('select[name="room_id"]').val();
      const date = $('input[name="date"]').val();
      const time = $('input[name="time"]').val();
      const dayOrNight = $('input[name="day_or_night"]').val();
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
    // Prevent opening modal if already open (avoid double-click issues)
    if (this.isModalOpen) return;

    const formattedDate = date.format("YYYY-MM-DD");
    // Use browser's current date as the source of truth for "today"
    const todayMoment = moment().startOf("day");
    const clickedDate = moment(date).startOf("day");

    // Block all past dates (before today)
    if (clickedDate.isBefore(todayMoment)) return;

    this.isModalOpen = true;
    this.highlightSelectedDate(formattedDate);
    const displayDate = date.format("MMMM D, YYYY");
    this.updateDateDisplay(displayDate);
    this.setInputDate(formattedDate);
    await this.fetchDayReservations(formattedDate);
    this.showEventModal();

    this.fetchAvailableTimeSlots(formattedDate, "all");
  }

  handleTimeSlotClick(element, time) {
    // Deselect ALL time slots first, then select this one
    $("#time-slots-container .time-slot").removeClass("selected-time");
    element.addClass("selected-time");

    // Extract just the HH:MM part for the time input (strip AM/PM)
    const timeOnly = time.replace(/ (AM|PM)$/i, "");
    $('input[name="time"]').val(timeOnly);

    // Auto-detect AM/PM from the selected time and set hidden input
    const isPM = /PM$/i.test(time);
    $('input[name="day_or_night"]').val(isPM ? "night" : "day");

    $(".duration-group").removeClass("d-none");
    this.fetchAvailableRooms();

    // Auto-scroll to duration section
    setTimeout(() => {
      const durationGroup = document.querySelector(".duration-group");
      if (durationGroup) {
        durationGroup.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    }, 100);
  }

  handleModalClose() {
    // Use .off first to prevent duplicate handlers from Stimulus re-connect
    $("#modal-view-event-add").off("hidden.bs.modal").on("hidden.bs.modal", () => {
      // Abort any pending AJAX requests to prevent stale callbacks
      this.pendingAjax.forEach(xhr => {
        if (xhr && xhr.readyState !== 4) {
          xhr.abort();
        }
      });
      this.pendingAjax = [];
      this.clearSelections();
      this.isModalOpen = false;

      // Force cleanup backdrop in case Bootstrap leaves it behind
      $(".modal-backdrop").remove();
      $("body").removeClass("modal-open").css("padding-right", "");
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

        // Handle day pass overage alert
        if (room.is_day_pass_overage) {
          this.showOverageAlert(room);
        } else {
          this.hideOverageAlert();
        }

        this.checkNeedsBilling(date);
      },
      error: (xhr, status, error) => {
        console.error("Error fetching room details:", error);
      },
    });
  }

  showOverageAlert(room) {
    const freeMinutes = room.included_minutes_remaining;
    const overageMinutes = room.overage_minutes;
    const overageRate = this.USDollar.format(room.overage_rate_hourly);
    const overagePrice = this.USDollar.format(room.reservation_price);

    let message = "";
    if (freeMinutes > 0) {
      message = `Your day pass includes ${freeMinutes} free minutes remaining. ` +
                `This booking exceeds that by ${overageMinutes} minutes. ` +
                `You will be charged ${overagePrice} at a rate of ${overageRate}/hour.`;
    } else {
      message = `You've used all your included meeting room time. ` +
                `This ${overageMinutes}-minute booking will cost ${overagePrice} ` +
                `at ${overageRate}/hour.`;
    }

    $(".day-pass-overage-alert .overage-message").text(message);
    $(".day-pass-overage-alert").removeClass("d-none");
  }

  hideOverageAlert() {
    $(".day-pass-overage-alert").addClass("d-none");
  }

  checkNeedsBilling(date) {
    const duration = $('input[name="duration"]').val();
    $.ajax({
      url: "/reservations/needs_billing",
      method: "GET",
      data: { date: date, duration: duration },
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
    const xhr = $.ajax({
      url: "/reservations/available_time_slots",
      method: "GET",
      data: { day: date, day_or_night: dayOrNight },
      success: (response) => {
        this.renderTimeSlots(response);
        callback && callback();
      },
      error: (xhr, status, error) => {
        if (status !== "abort") {
          console.error("Error fetching time slots:", error);
        }
      },
    });
    this.pendingAjax.push(xhr);
  }

  fetchAvailableRooms() {
    const date = $('input[name="date"]').val();
    const time = $('input[name="time"]').val();
    const duration = $('input[name="duration"]').val();
    const dayOrNight = $('input[name="day_or_night"]').val();

    if (!date || !time || !duration) return;

    const xhr = $.ajax({
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
        this.hideOverageAlert();

        $(".available-room-group").removeClass("d-none");
        $(".room-details").addClass("d-none");
        $(".price-container").addClass("d-none");
        this.renderAvailableRooms(response);
      },
      error: (xhr, status, error) => {
        if (status !== "abort") {
          console.error("Error fetching available rooms:", error);
        }
      },
    });
    this.pendingAjax.push(xhr);
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
  prefillReservationForm(date, time) {
    const dayClickDate = moment(date).startOf("day");

    this.handleDayClick(dayClickDate);

    this.fetchAvailableTimeSlots(date, "all", () => {
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
    // Clear time slot handlers and content to prevent stale state
    $("#time-slots-container").off("click.timeslot touchend.timeslot");
    $("#time-slots-container").empty();
    $('input[name="time"]').val("");

    $(".duration-group").addClass("d-none");
    $(".available-room-group").addClass("d-none");

    $(".duration-slot").removeClass("selected-time");
    $('input[name="duration"]').val("");

    // Default AM/PM based on current time
    const currentHour = new Date().getHours();
    $('input[name="day_or_night"]').val(currentHour >= 12 ? "night" : "day");

    $("#add-reservation button[type='submit']").attr("disabled", true);

    $(".note-container").addClass("d-none");
    $("#reservation-note").val("");

    this.needsBilling = false;
    this.hideBillingSection();
    this.hideOverageAlert();
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
    // Remove old event handlers and clear content
    timeSlotsContainer.off("click.timeslot touchend.timeslot");
    timeSlotsContainer.empty();

    if (timeSlots.length === 0) {
      timeSlotsContainer.append("<p>No available time slots.</p>");
      return;
    }

    timeSlots.forEach((slot) => {
      const timeSlotElement = $(`<div class="time-slot">${slot}</div>`);
      timeSlotsContainer.append(timeSlotElement);
    });

    // Use event delegation so only one handler exists for all time slots
    timeSlotsContainer.on("click.timeslot touchend.timeslot", ".time-slot", (e) => {
      e.preventDefault();
      e.stopPropagation();

      // Debounce guard: ignore rapid duplicate fires (touch + click)
      if (this._timeSlotClickLock) return;
      this._timeSlotClickLock = true;
      setTimeout(() => { this._timeSlotClickLock = false; }, 400);

      const clicked = $(e.currentTarget);
      const slotText = clicked.text();
      this.handleTimeSlotClick(clicked, slotText);
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

  initializeBottomSheet() {
    const handle = document.querySelector(".bottom-sheet-handle");
    if (!handle) return;

    let startY = 0;
    let currentY = 0;

    handle.addEventListener("touchstart", (e) => {
      if (window.innerWidth > 768) return;
      startY = e.touches[0].clientY;
      currentY = startY;
    }, { passive: true });

    handle.addEventListener("touchmove", (e) => {
      if (window.innerWidth > 768) return;
      currentY = e.touches[0].clientY;
    }, { passive: true });

    handle.addEventListener("touchend", () => {
      if (window.innerWidth > 768) return;
      const swipeDistance = currentY - startY;
      if (swipeDistance > 100) {
        $("#modal-view-event-add").modal("hide");
      }
    });
  }
}
