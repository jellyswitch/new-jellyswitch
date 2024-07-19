require "rails_helper"

RSpec.describe Room, type: :model do
  describe "#paid_room?" do
    context "when hourly_rate_in_cents is greater than 0 and room is rentable" do
      it "returns true" do
        room = build(:room, hourly_rate_in_cents: 1000, rentable: true)
        expect(room).to be_paid_room
      end
    end

    context "when hourly_rate_in_cents is 0 and room is rentable" do
      it "returns false" do
        room = build(:room, hourly_rate_in_cents: 0, rentable: true)
        expect(room).not_to be_paid_room
      end
    end

    context "when hourly_rate_in_cents is greater than 0 and room is not rentable" do
      it "returns false" do
        room = build(:room, hourly_rate_in_cents: 100, rentable: false)
        expect(room).not_to be_paid_room
      end
    end
  end

  describe ".unavailable" do
    it "returns unavailable rooms for give date, time and duration" do
      Timecop.travel Time.zone.parse("2024-06-15 10:00:00") do
        room = create(:room, name: "Small Meeting Room")

        create(:reservation, room: room, datetime_in: Time.current.change(hour: 15), minutes: 30)

        result = Room.unavailable(date: Time.zone.today, time: 14, duration: 120)
        expect(result).to include(room)
      end
    end
  end

  describe ".available" do
    it "returns available rooms for give date, time and duration" do
      Timecop.travel Time.zone.parse("2024-06-15 10:00:00") do
        room = create(:room, name: "Small Meeting Room")

        create(:reservation, room: room, datetime_in: Time.current.change(hour: 13), minutes: 30)

        result = Room.available(date: Time.zone.today, time: 14, duration: 120)
        expect(result).to include(room)
      end
    end
  end

  describe "available?" do
    let(:room) { create(:room) }

    context "when room is available for the given time, and duration" do
      it "returns true" do
        room.reservations.destroy_all # Ensure room is available

        expect(room.available?(start_time: Time.zone.now, duration: 120)).to be true
      end
    end

    context "when room is occupied for the given time and duration" do
      it "returns false" do
        reserved_time = Time.current.change(hour: 15)
        create(:reservation, room: room, datetime_in: reserved_time, minutes: 60)

        expect(room.available?(start_time: reserved_time + 30.minutes, duration: 30)).to be false
      end
    end

    context "when room is occupied exactly at the end time" do
      it "returns true" do
        reserved_time = Time.current.change(hour: 15)

        reservation = create(:reservation, room: room, datetime_in: reserved_time, minutes: 60)

        expect(room.available?(start_time: reservation.datetime_out, duration: 30)).to be true
      end
    end
  end

  describe "#calculate_available_durations" do
    it "returns an array of available durations for the given start time" do
      available_room = create(:room)
      reserved_time = Time.current.change(hour: 15)
      create(:reservation, room: available_room, datetime_in: reserved_time, minutes: 60)

      result = available_room.calculate_available_durations(start_time: Time.current.change(hour: 14))

      expect(result).to eq([30, 60])
    end
  end

  describe "has_av?" do
    context "when one of the amenity names is 'AV Equipment'" do
      it "returns true" do
        room = create(:room)

        create(:amenity, name: "AV Equipment", room: room)
        create(:amenity, name: "Random #1", room: room)

        expect(room).to have_av
      end
    end

    context "when all the amenity names is not 'AV Equipment'" do
      it "returns false" do
        room = create(:room)
        create(:amenity, name: "Random #1", room: room)
        create(:amenity, name: "Random #1", room: room)

        expect(room).not_to have_av
      end
    end
  end

  describe "has_whiteboard?" do
    context "when one of the amenity names is 'Whiteboard'" do
      it "returns true" do
        room = create(:room)

        create(:amenity, name: "Whiteboard", room: room)
        create(:amenity, name: "Random #1", room: room)

        expect(room).to have_whiteboard
      end
    end

    context "when all the amenity names is not 'Whiteboard'" do
      it "returns false" do
        room = create(:room)
        create(:amenity, name: "Random #1", room: room)
        create(:amenity, name: "Random #2", room: room)

        expect(room).not_to have_whiteboard
      end
    end
  end
end
