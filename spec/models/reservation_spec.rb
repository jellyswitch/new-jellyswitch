require "rails_helper"

RSpec.describe Reservation, type: :model do
  let(:location) { Location.first }
  let(:room) { create(:room, name: "Meeting Room 3A", hourly_rate_in_cents: 1000, location: location) }

  describe "associations" do
    it "has and belongs to many amenities" do
      expect(Reservation.reflect_on_association(:amenities).macro).to eq(:has_and_belongs_to_many)
    end
  end

  describe "scopes" do
    let!(:ongoing_reservation) { create(:reservation, datetime_in: Time.zone.now, room: room) }
    let!(:future_reservation) { create(:reservation, :future, room: room) }

    it "returns only ongoing reservations" do
      expect(Reservation.ongoing).to contain_exactly(ongoing_reservation)
    end

    context "for_location_id" do
      let(:location_2) { create(:location) }
      let!(:room_2) { create(:room, location: location_2) }
      let!(:reservation) { create(:reservation, room: room_2) }

      it "returns only reservations for the given location" do
        expect(Reservation.for_location_id(location_2.id)).to contain_exactly(reservation)
      end

      it "returns all reservations if location_id is nil" do
        expect(Reservation.for_location_id(nil)).to contain_exactly(ongoing_reservation, future_reservation, reservation)
      end
    end
  end

  describe "#datetime_out" do
    let(:reservation) { build(:reservation, datetime_in: Time.zone.parse("2024-07-01 07:15:00"), minutes: 60) }

    it "returns the datetime_in plus the minutes" do
      expect(reservation.datetime_out).to eq(Time.zone.parse("2024-07-01 08:15:00"))
    end
  end

  describe "timing status" do
    let(:ongoing_reservation) { build(:reservation, datetime_in: Time.current) }
    let(:future_reservation) { build(:reservation, :future) }

    describe "#ongoing?" do
      it "returns true for ongoing reservation" do
        expect(ongoing_reservation).to be_ongoing
        expect(future_reservation).not_to be_ongoing
      end
    end

    describe "#future?" do
      it "returns true for future reservation" do
        expect(future_reservation).to be_future
        expect(ongoing_reservation).not_to be_future
      end
    end
  end

  describe "#end_now!" do
    let(:reservation) { create(:reservation, datetime_in: Time.current, room: room, minutes: 60) }

    before do
      Timecop.freeze(reservation.datetime_in)
    end

    after do
      Timecop.return
    end

    def travel_and_end_reservation(travel_time)
      Timecop.travel(travel_time)
      reservation.end_now!
      reservation.reload
    end

    context "when ended before the original end time" do
      let(:new_duration) { 35.minutes }

      before { travel_and_end_reservation(reservation.datetime_in + new_duration) }

      it "updates the minutes to the actual duration" do
        expect(reservation.minutes).to eq(new_duration.to_i / 60)
      end

      it "marks the reservation as ended early" do
        expect(reservation).to be_ended_early
      end
    end

    context "when ended after the original end time" do
      let(:late_duration) { 90.minutes }

      before { travel_and_end_reservation(reservation.datetime_in + late_duration) }

      it "does not change the original minutes" do
        expect(reservation.minutes).to eq(60)
      end

      it "still marks the reservation as ended early" do
        expect(reservation).to be_ended_early
      end
    end
  end

  describe "#room_price" do
    let(:reservation) { build(:reservation, room: room, minutes: 180) }

    context "when the reservation is paid" do
      before { reservation.paid = true }

      it "returns the actual price of the room" do
        expect(reservation.room_price).to eq(180 / 60 * room.hourly_rate_in_cents)
      end
    end

    context "when the reservation is not paid" do
      before { reservation.paid = false }

      it "returns zero" do
        expect(reservation.room_price).to eq(0)
      end
    end
  end

  describe "#amenity_price" do
    let(:reservation) { build(:reservation, room: room, minutes: 180) }
    let(:amenity1) { create(:amenity, name: "Amenity 1", room: room) }
    let(:amenity2) { create(:amenity, name: "Amenity 2", room: room) }

    before do
      reservation.amenities = [amenity1, amenity2]
      reservation.save
    end

    context "when user should charge for reservation" do
      before { allow_any_instance_of(User).to receive(:should_charge_for_reservation?).and_return(true) }

      it "returns the total regular amenity price for non-members" do
        expected_price = Money.from_amount(amenity1.price + amenity2.price, "USD").cents
        expect(reservation.amenity_price).to eq(expected_price)
      end
    end

    context "when user should not charge for reservation" do
      before { allow_any_instance_of(User).to receive(:should_charge_for_reservation?).and_return(false) }

      it "returns the total membership amenity price for non-members" do
        expected_price = Money.from_amount(amenity1.membership_price + amenity2.membership_price, "USD").cents
        expect(reservation.amenity_price).to eq(expected_price)
      end
    end
  end

  describe "#charge_amount" do
    let(:room) { create(:room, hourly_rate_in_cents: 1000) }
    let(:reservation) { create(:reservation, room: room, minutes: 60) }

    context "with no amenities" do
      it "calculates the correct amount" do
        expect(reservation.charge_amount).to eq(1000)
      end
    end

    context "with amenities" do
      let(:amenity1) { Amenity.create(name: "Amenity 1", price: 10, room: room) }
      let(:amenity2) { Amenity.create(name: "Amenity 2", price: 15, room: room) }

      before { reservation.amenities = [amenity1, amenity2] }

      it "calculates the correct amount including amenities" do
        expected_amount = 1000 + (10 + 15) * 100
        expect(reservation.charge_amount).to eq(expected_amount)
      end
    end
  end

  describe "#amenity_names" do
    let(:reservation) { create(:reservation, room: room, amenities: [amenity1, amenity2]) }
    let(:amenity1) { create(:amenity, name: "Biscuit", price: 10, room: room) }
    let(:amenity2) { create(:amenity, name: "Presenter", price: 15, room: room) }

    it "returns a list of amenity names" do
      expected_names = ["Biscuit", "Presenter"].join(", ")
      amenities_name = reservation.amenity_names

      expect(amenities_name).to eq(expected_names)
    end
  end

  describe "#additional_duration_price" do
    let(:ongoing_reservation) { create(:reservation, room: room, minutes: 60) }

    context "when paid? is true" do
      it "returns the correct calculation" do
        ongoing_reservation.update(paid: true)
        extra_minutes = 30
        expected_price = ((room.hourly_rate_in_cents / 60.0) * extra_minutes).to_i
        expect(ongoing_reservation.additional_duration_price(extra_minutes)).to eq(expected_price)
      end
    end

    context "when paid? is false" do
      it "returns 0" do
        ongoing_reservation.update(paid: false)
        extra_minutes = 30
        expect(ongoing_reservation.additional_duration_price(extra_minutes)).to eq(0)
      end
    end
  end

  describe "DST transition" do
    before { Time.zone = "Pacific Time (US & Canada)" }

    let(:spring_forward_date) { Time.zone.parse("2024-03-10") }
    let(:fall_back_date) { Time.zone.parse("2024-11-03") }

    describe "Spring Forward" do
      it "handles the spring forward transition correctly" do
        reservation = create(:reservation, datetime_in: spring_forward_date.change(hour: 2, min: 00), minutes: 30)

        Timecop.freeze(spring_forward_date.change(hour: 1, min: 59, sec: 59)) do
          expect(Time.zone.now.hour).to eq(1)
          expect(reservation).to be_future

          Timecop.travel(2.minutes)

          expect(Time.zone.now.hour).to eq(3)
          expect(reservation.reload.datetime_in.hour).to eq(3)
          expect(reservation).to be_ongoing
          expect(reservation.datetime_out - reservation.datetime_in).to eq(30.minutes)
        end
      end
    end

    describe "Fall Back" do
      it "handles the fallback transition correctly" do
        start_time = fall_back_date.change(hour: 1, min: 30)
        reservation = create(:reservation, datetime_in: start_time, minutes: 60)

        Timecop.freeze(start_time) do
          expect(Time.zone.now.hour).to eq(1)
          expect(reservation).to be_ongoing

          Timecop.travel(65.minutes)

          expect(Time.zone.now.hour).to eq(1)
          expect(reservation).not_to be_ongoing
          expect(reservation.datetime_out).to be < Time.zone.now
          expect(reservation.datetime_out - reservation.datetime_in).to eq(60.minutes)

          Timecop.travel(1.hour)

          expect(Time.zone.now.hour).to eq(2)
        end
      end
    end
  end
end
