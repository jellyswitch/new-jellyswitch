require "rails_helper"

RSpec.describe Notifiable::Reservation do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }

  def reservation_for(room:)
    r = Reservation.new(room: room, user: user, datetime_in: 2.days.from_now.change(hour: 12), minutes: 60)
    r.save!(validate: false)
    r
  end

  describe "#create_feed_item" do
    it "creates a generic 'reservation' feed card for a FREE room" do
      free_room = create(:room, operator: operator, location: location, hourly_rate_in_cents: 0)
      r = reservation_for(room: free_room)
      expect { described_class.new(r).send(:create_feed_item) }
        .to change { FeedItem.where("blob->>'type' = ?", "reservation").count }.by(1)
    end

    it "does NOT create the generic card for a PAID room (Notifiable::PaidRoomReservation owns that card — prevents duplicate feed cards)" do
      paid_room = create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000, rentable: true)
      r = reservation_for(room: paid_room)
      expect { described_class.new(r).send(:create_feed_item) }
        .not_to change(FeedItem, :count)
    end
  end
end
