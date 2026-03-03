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
    let(:valid_params) do
      {
        room_id: room.id,
        date: Time.current.tomorrow.to_date.to_s,
        time: "10:00",
        duration: "60",
        day_or_night: "day",
        note: "Test reservation",
        amenity_ids: [amenity.id]
      }
    end

    context "with valid params" do
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
