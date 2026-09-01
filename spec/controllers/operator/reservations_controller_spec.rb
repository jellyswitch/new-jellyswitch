require 'rails_helper'

RSpec.describe Operator::ReservationsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:room) { create(:room, operator: operator, location: location) }
  let!(:reservation) { create(:reservation, user: regular_user, room: room, datetime_in: 1.hour.ago, minutes: 120) }
  let(:amenity) { create(:amenity, room: room) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_user).and_return(regular_user)
    regular_user.user_payment_profiles.first.update stripe_customer_id: "cus_123"
  end

  describe "GET #show" do
    before { get :show, params: { id: reservation.id } }

    it "assigns @reservation" do
      expect(assigns(:reservation)).to eq(reservation)
    end

    it "decorates the reservation" do
      expect(assigns(:reservation)).to be_decorated
    end
  end

  describe "GET #calendar" do
    before { get :calendar }

    context "with reserve_now parameter" do
      before do
        Timecop.freeze(Time.zone.parse("2025-01-15 09:00:00"))
        get :calendar, params: { reserve_now: true }
      end
      after { Timecop.return }

      it "assigns @current_date" do
        expect(assigns(:current_date)).to eq(Time.zone.today)
      end

      it "calculates nearest time slot" do
        expect(assigns(:nearest_time_slot)).to be_present
      end

      it "assigns @day_or_night" do
        expect(assigns(:day_or_night)).to be_in(["day", "night"])
      end
    end
  end


  describe "GET #available_time_slots" do
    let(:valid_params) do
      {
        day: Time.current.to_date.to_s,
        day_or_night: "day"
      }
    end

    it "returns available time slots" do
      get :available_time_slots, params: valid_params, format: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_an(Array)
    end

    context "with invalid params" do
      it "returns error" do
        get :available_time_slots, params: {}, format: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET #available_rooms" do
    let(:valid_params) do
      {
        date: Time.current.to_date.to_s,
        time: "10:00",
        duration: "60",
        day_or_night: "day"
      }
    end

    it "returns available rooms" do
      get :available_rooms, params: valid_params, format: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_an(Array)
    end

    context "with invalid params" do
      it "returns error" do
        get :available_rooms, params: {}, format: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET #room_price_and_details" do
    let(:valid_params) do
      {
        room_id: room.id,
        duration: "60",
        date: Time.current.to_date.to_s
      }
    end

    it "returns room details and pricing" do
      get :room_price_and_details, params: valid_params, format: :json
      expect(response).to have_http_status(:success)
      response_body = JSON.parse(response.body)
      expect(response_body).to include('id', 'name', 'hourly_price', 'capacity')
    end
  end

  describe "POST #create" do
    # Pinned to a guaranteed OPEN weekday — member self-serve creates enforce
    # posted hours (EnforcePostedHours), and a relative "tomorrow" lands on a
    # closed Saturday when the suite runs on a Friday.
    let(:booking_date) { Date.current.next_occurring(:tuesday) + 7 }
    let(:valid_params) do
      {
        room_id: room.id,
        date: booking_date.to_s,
        time: "10:00",
        duration: "60",
        day_or_night: "day",
        note: "Test reservation",
        amenity_ids: [amenity.id]
      }
    end

    context "with valid params" do
      # ADR 0019: the default factory room is $0 + include_with_day_pass, so
      # booking it now requires day-pass coverage (enforce_coverage). These
      # examples cover the basic create mechanics, so give the member a day pass
      # for the booking date → already_covered → the booking proceeds.
      let!(:coverage_pass) do
        create(:day_pass, user: regular_user, billable: regular_user, operator: operator,
               location: location, day: booking_date)
      end

      before do
        allow(SendUpcomingReservationReminderJob).to receive_message_chain(:set, :perform_later)
        allow(Stripe::InvoiceItem).to receive(:create).and_return(true)
        invoice = double(id: "invoice_id", customer: "cus_123",
          created: Time.current.to_i,
          due_date: Time.current.tomorrow.to_i,
          status: "open",
          amount_due: 1000,
          amount_paid: 0,
          number: "123",
          lines: []
        )
        allow(Stripe::Invoice).to receive(:create).and_return(invoice)
        allow(Stripe::Invoice).to receive(:retrieve).and_return(invoice)
        allow(Billing::Reservations::ChargeAtBooking).to receive(:call!) { |context| context }
      end

      it "creates a new reservation" do
        expect {
          post :create, params: valid_params
        }.to change(Reservation, :count).by(1)
      end

      it "sets success flash message" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end

      it "allows a booking at exactly the 4h free-room cap" do
        expect {
          post :create, params: valid_params.merge(duration: "240")
        }.to change(Reservation, :count).by(1)
      end
    end

    context "over the duration cap" do
      # Server-side backstop (EnforceDurationCap): the form's slider tops out
      # at the cap, but a hand-rolled POST could send any duration. The step
      # runs before anything persists or touches Stripe, so no coverage pass
      # or billing stubs are needed — the booking must die first.
      let(:over_cap_params) { valid_params.merge(duration: "300") }

      it "rejects a free-room booking over the 4h member cap" do
        expect {
          post :create, params: over_cap_params
        }.not_to change(Reservation, :count)
        expect(flash[:error]).to eq("#{room.name} can be booked for up to 4 hours.")
      end

      it "rejects the stripeToken path too, before any card is attached" do
        expect(Billing::Payment::UpdateUserPayment).not_to receive(:call!)
        expect {
          post :create, params: over_cap_params.merge(stripeToken: "tok_visa")
        }.not_to change(Reservation, :count)
        expect(flash[:error]).to eq("#{room.name} can be booked for up to 4 hours.")
      end
    end

    context "with stripeToken" do
      let(:success_result) { OpenStruct.new(success?: true, reservation: reservation) }

      it "uses UpdateBillingAndCreateRoomReservation when token is present" do
        expect(Billing::Reservations::UpdateBillingAndCreateRoomReservation)
          .to receive(:call).and_return(success_result)
        post :create, params: valid_params.merge(stripeToken: "tok_visa")
      end

      it "uses CreateRoomReservation when no token is present" do
        expect(Billing::Reservations::CreateRoomReservation)
          .to receive(:call).and_return(success_result)
        post :create, params: valid_params
      end
    end

    context "with invalid params" do
      before do
        allow(Billing::Reservations::CreateRoomReservation)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "sets error flash message" do
        post :create, params: valid_params
        expect(flash[:error]).to be_present
      end
    end
  end

  describe "POST #create_reservation" do
    # Classic wizard endpoint (choose-member flow) — reachable by non-staff
    # members booking themselves, so the EnforceDurationCap and
    # EnforcePostedHours backstops both apply, each gated on the BOOKER: the
    # interactors read context.user (the booked member), so staff booking on
    # behalf must stay unflagged or the member's limits would block the staff
    # booking. Same guaranteed-open-weekday date pin as POST #create.
    let(:wizard_params) do
      {
        room_id: room.id,
        day: (Date.current.next_occurring(:tuesday) + 7).to_s,
        hour: "10:00am",
        duration: "300"
      }
    end

    context "as a member booking themselves" do
      it "rejects a free-room booking over the 4h member cap" do
        expect {
          post :create_reservation, params: wizard_params
        }.not_to change(Reservation, :count)
        expect(flash[:error]).to eq("#{room.name} can be booked for up to 4 hours.")
      end

      # Nash backstop: the booker has no subscription/lease, so EnforcePostedHours
      # applies (factory location posts 6:00 AM – 8:00 PM). Runs first in the
      # organizer, so nothing persists and no billing stubs are needed.
      it "rejects a booking outside posted hours" do
        expect {
          post :create_reservation, params: wizard_params.merge(hour: "9:00pm", duration: "60")
        }.not_to change(Reservation, :count)
        expect(flash[:error]).to eq("#{location.name} is open #{location.posted_hours_label}. Rooms can be booked during open hours.")
      end

      it "still allows an active subscriber to book outside posted hours (members book 24/7)" do
        create(:subscription, subscribable: regular_user, billable: regular_user,
               plan: create(:plan, operator: operator, location: location))
        allow(SendUpcomingReservationReminderJob).to receive_message_chain(:set, :perform_later)
        allow(Billing::Reservations::ChargeAtBooking).to receive(:call!) { |context| context }

        expect {
          post :create_reservation, params: wizard_params.merge(hour: "9:00pm", duration: "60")
        }.to change(Reservation, :count).by(1)
        expect(flash[:error]).to be_nil
      end
    end

    # ADR 0019 in the wizard: the default factory room is $0 + include_with_day_pass,
    # so a member booking it here must commit day-pass coverage (enforce_coverage,
    # gated on the BOOKER like the other flags). Before this the wizard was the one
    # booking surface with no coverage enforcement — free room, no burn, no access.
    context "as a member booking an included room (coverage)" do
      let(:booking_day) { Date.current.next_occurring(:tuesday) + 7 }
      let(:coverage_params) { wizard_params.merge(duration: "60") }

      it "blocks an uncovered booking with the buy prompt instead of a free room" do
        expect {
          post :create_reservation, params: coverage_params
        }.not_to change(Reservation, :count)
        expect(flash[:error]).to match(/day pass/i)
      end

      it "books when the member already holds a pass for the date" do
        create(:day_pass, user: regular_user, billable: regular_user, operator: operator,
               location: location, day: booking_day)
        allow(SendUpcomingReservationReminderJob).to receive_message_chain(:set, :perform_later)
        allow(Billing::Reservations::ChargeAtBooking).to receive(:call!) { |context| context }

        expect {
          post :create_reservation, params: coverage_params
        }.to change(Reservation, :count).by(1)
        expect(flash[:error]).to be_nil
      end

      # ADR 0029: the wizard confirm page has no coverage UI and sends no flags,
      # so a bundle holder must burn automatically rather than dead-end in the
      # buy prompt (the Pratik incident, on the calendar sheet's flagless POST).
      it "burns a bundle pass automatically for a bundle holder" do
        t = create(:day_pass_type, operator: operator, location: location,
                   included_meeting_room_minutes: 120, amount_in_cents: 4000,
                   available: true, visible: true)
        bundle = DayPassBundle.create!(user: regular_user, operator: operator, location: location,
                                       day_pass_type: t, quantity_purchased: 5, passes_remaining: 5,
                                       purchased_at: Time.current)
        allow(SendUpcomingReservationReminderJob).to receive_message_chain(:set, :perform_later)
        allow(Billing::Reservations::ChargeAtBooking).to receive(:call!) { |context| context }

        expect {
          post :create_reservation, params: coverage_params
        }.to change(Reservation, :count).by(1)
        expect(bundle.reload.passes_remaining).to eq(4)
        expect(regular_user.day_passes.for_day(booking_day).count).to eq(1)
      end
    end

    # The staff on-behalf examples below also pin the coverage gate's other half:
    # they book this same included room for an uncovered member and must keep
    # succeeding — enforce_coverage stays off for admin/manager bookers.
    context "as staff booking on behalf of a member" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        allow(SendUpcomingReservationReminderJob).to receive_message_chain(:set, :perform_later)
        allow(Billing::Reservations::ChargeAtBooking).to receive(:call!) { |context| context }
      end

      it "allows a 300-minute free-room booking for the member" do
        expect {
          post :create_reservation, params: wizard_params.merge(user_id: regular_user.id)
        }.to change(Reservation, :count).by(1)

        booked = Reservation.order(:id).last
        expect(booked.user).to eq(regular_user)
        expect(booked.minutes).to eq(300)
        expect(flash[:error]).to be_nil
      end

      # The booked member has no subscription (not exempt), so this passes only
      # because the flag is gated on the BOOKER — a blanket enforce_posted_hours
      # would wrongly block staff booking on behalf outside posted hours.
      it "allows an outside-posted-hours booking for the member" do
        expect {
          post :create_reservation, params: wizard_params.merge(user_id: regular_user.id, hour: "9:00pm", duration: "60")
        }.to change(Reservation, :count).by(1)
        expect(flash[:error]).to be_nil
      end
    end
  end

  describe "POST #update_billing_and_create_reservation" do
    # Same wizard, new-card variant (books for current_user). The posted-hours
    # and cap steps run before UpdateUserPayment, so a blocked request must
    # die without attaching a card.
    it "rejects a member booking over the cap before any card is attached" do
      expect(Billing::Payment::UpdateUserPayment).not_to receive(:call!)
      expect {
        post :update_billing_and_create_reservation, params: {
          room_id: room.id,
          day: (Date.current.next_occurring(:tuesday) + 7).to_s,
          hour: "10:00am",
          duration: "300",
          stripeToken: "tok_visa"
        }
      }.not_to change(Reservation, :count)
      expect(flash[:error]).to eq("#{room.name} can be booked for up to 4 hours.")
    end

    it "rejects a booking outside posted hours before any card is attached" do
      expect(Billing::Payment::UpdateUserPayment).not_to receive(:call!)
      expect {
        post :update_billing_and_create_reservation, params: {
          room_id: room.id,
          day: (Date.current.next_occurring(:tuesday) + 7).to_s,
          hour: "9:00pm",
          duration: "60",
          stripeToken: "tok_visa"
        }
      }.not_to change(Reservation, :count)
      expect(flash[:error]).to eq("#{location.name} is open #{location.posted_hours_label}. Rooms can be booked during open hours.")
    end

    # ADR 0019: a non-member bundle/no-pass holder has should_charge_for_reservation?
    # true, so with no card on file the confirm page routes them through THIS action —
    # it must enforce coverage exactly like create_reservation (same booker gate).
    context "booking an included room (coverage)" do
      let(:booking_day) { Date.current.next_occurring(:tuesday) + 7 }
      let(:card_params) do
        { room_id: room.id, day: booking_day.to_s, hour: "10:00am", duration: "60", stripeToken: "tok_visa" }
      end

      before { allow(Billing::Payment::UpdateUserPayment).to receive(:call!) }

      it "blocks an uncovered booking with the buy prompt instead of a free room" do
        expect {
          post :update_billing_and_create_reservation, params: card_params
        }.not_to change(Reservation, :count)
        expect(flash[:error]).to match(/day pass/i)
      end

      it "books when the member already holds a pass for the date" do
        create(:day_pass, user: regular_user, billable: regular_user, operator: operator,
               location: location, day: booking_day)
        allow(SendUpcomingReservationReminderJob).to receive_message_chain(:set, :perform_later)
        allow(Billing::Reservations::ChargeAtBooking).to receive(:call!) { |context| context }

        expect {
          post :update_billing_and_create_reservation, params: card_params
        }.to change(Reservation, :count).by(1)
        expect(flash[:error]).to be_nil
      end
    end
  end

  describe "GET #needs_billing" do
    let(:date) { Time.current.tomorrow.to_date.to_s }

    context "when user should be charged and has no billing" do
      before do
        allow(regular_user).to receive(:should_charge_for_reservation?).and_return(true)
        allow(regular_user).to receive(:has_billing_for_location?).and_return(false)
      end

      it "returns needs_billing true" do
        get :needs_billing, params: { date: date }, format: :json
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)["needs_billing"]).to eq(true)
      end
    end

    context "when user has billing on file" do
      before do
        allow(regular_user).to receive(:should_charge_for_reservation?).and_return(true)
        allow(regular_user).to receive(:has_billing_for_location?).and_return(true)
      end

      it "returns needs_billing false" do
        get :needs_billing, params: { date: date }, format: :json
        expect(JSON.parse(response.body)["needs_billing"]).to eq(false)
      end
    end

    context "when reservation is free" do
      before do
        allow(regular_user).to receive(:should_charge_for_reservation?).and_return(false)
        allow(regular_user).to receive(:has_billing_for_location?).and_return(false)
      end

      it "returns needs_billing false" do
        get :needs_billing, params: { date: date }, format: :json
        expect(JSON.parse(response.body)["needs_billing"]).to eq(false)
      end
    end
  end

  describe "GET #available_extension_durations" do
    it "returns available durations" do
      get :available_extension_durations, params: { id: reservation.id }, format: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_an(Array)
    end
  end

  describe "GET #calculate_additional_hour_price" do
    let(:valid_params) do
      {
        id: reservation.id,
        duration: "60"
      }
    end

    it "returns price calculation" do
      get :calculate_additional_hour_price, params: valid_params, format: :json
      expect(response).to have_http_status(:success)
      response_body = JSON.parse(response.body)
      expect(response_body).to include('additional_price', 'new_end_time', 'should_charge')
    end
  end

  describe "POST #extend_reservation" do
    let(:valid_params) do
      {
        id: reservation.id,
        duration: "60"
      }
    end

    context "when extension succeeds" do
      before do
        allow(Billing::Reservations::ExtendReservation)
          .to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "extends the reservation" do
        post :extend_reservation, params: valid_params
        expect(flash[:notice]).to match(/extended successfully/)
      end
    end

    context "when extension fails" do
      before do
        allow(Billing::Reservations::ExtendReservation)
          .to receive(:call).and_return(OpenStruct.new(success?: false, message: "Error"))
      end

      it "sets error flash message" do
        post :extend_reservation, params: valid_params
        expect(flash[:error]).to be_present
      end
    end

    # IDOR guard: the reservation belongs to regular_user; a different member
    # must not be able to extend it (and charge the owner). extend_reservation?
    # = owner-or-staff.
    context "when a different member (not the owner) attempts it" do
      let(:other_user) { create(:user, operator: operator, original_location: location) }

      before { allow(controller).to receive(:current_user).and_return(other_user) }

      it "does not extend and is not authorized" do
        expect(Billing::Reservations::ExtendReservation).not_to receive(:call)
        post :extend_reservation, params: valid_params
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "POST #end_now" do
    it "ends the reservation early" do
      allow(controller).to receive(:current_user).and_return(admin_user)

      post :end_now, params: { id: reservation.id }
      expect(flash[:notice]).to match(/ended early successfully/)
    end
  end

  describe "PUT #update_note" do
    let(:valid_params) do
      {
        id: reservation.id,
        reservation: { note: "Updated note" }
      }
    end

    it "updates the reservation note" do
      put :update_note, params: valid_params
      expect(flash[:notice]).to match(/updated successfully/)
    end

    it "forbids a non-owner member from editing another member's note" do
      other_member = create(:user, operator: operator, original_location: location)
      allow(controller).to receive(:current_user).and_return(other_member)

      put :update_note, params: { id: reservation.id, reservation: { note: "Hijacked" } }

      expect(response).to have_http_status(:redirect) # Pundit denial
      expect(reservation.reload.note).not_to eq("Hijacked")
    end
  end

  describe "GET #daily_counts" do
    let(:valid_params) do
      {
        start_date: Time.current.to_date.to_s,
        end_date: Time.current.to_date.tomorrow.to_s
      }
    end

    it "returns daily reservation counts" do
      get :daily_counts, params: valid_params, format: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_a(Hash)
    end
  end

  describe "GET #daily_details" do
    let(:valid_params) do
      {
        date: Time.current.to_date.to_s
      }
    end

    it "returns reservation details for the day" do
      get :daily_details, params: valid_params, format: :json
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to be_an(Array)
    end

    context "with invalid date" do
      it "returns error" do
        get :daily_details, params: { date: "invalid" }, format: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET #today" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "assigns @rooms with today's reservations" do
      get :today
      expect(assigns(:rooms)).to be_present
    end
  end

  describe "helper methods" do
    include CreditHelper
    include ReservationHelper

    it "calculates reservation cost" do
      expect(reservation_cost(room, 60)).to eq(room.credit_cost)
    end

    it "calculates ending balance" do
      initial_balance = regular_user.credit_balance
      expect(ending_balance(regular_user, 10)).to eq(initial_balance - 10)
    end

    it "finds today's reservations" do
      result = find_todays_reservations(location)
      expect(result).to be_an(Array)
    end

    it "calculates available time slots" do
      result = calculate_available_time_slots(Time.current.to_date, "day")
      expect(result).to be_an(Array)
    end


    it "calculates nearest time slot" do
      Timecop.freeze(Time.zone.parse("2025-01-15 09:00:00")) do
        result = calculate_nearest_time_slot(Time.current.to_date)
        expect(result).to be_a(Time)
      end
    end
  end

  describe "DST handling" do
    include ReservationHelper
    include CreditHelper

    it "creates reservation at correct time across DST boundary" do
      # March 9, 2025 is spring-forward day
      Timecop.freeze(Time.zone.parse("2025-03-03 10:00:00")) do
        zone = ActiveSupport::TimeZone[location.time_zone]
        target_date = Date.parse("2025-03-09")
        hour = Time.strptime("9:00", "%I:%M") + 12.hours # 9pm
        result = zone.local(target_date.year, target_date.month, target_date.day, hour.hour, hour.min)
        expect(result.hour).to eq(21)
        expect(result.utc_offset).to eq(-7 * 3600) # PDT
      end
    end
  end
end
