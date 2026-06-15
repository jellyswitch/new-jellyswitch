# == Schema Information
#
# Table name: amenities
#
#  id               :bigint(8)        not null, primary key
#  membership_price :float            default(0.0)
#  name             :string
#  price            :float            default(0.0)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  room_id          :bigint(8)        not null
#
# Indexes
#
#  index_amenities_on_room_id  (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (room_id => rooms.id)
#
require "rails_helper"

RSpec.describe Amenity, type: :model do
  let(:room) { create(:room, name: "Test Room") }
  let(:amenity) { build(:amenity, name: "WiFi", price: 5.0, room: room) }

  after(:each) do
    room.destroy
    Amenity.destroy_all
  end

  describe "associations" do
    it "has and belongs to many reservations" do
      expect(Amenity.reflect_on_association(:reservations).macro).to eq(:has_and_belongs_to_many)
    end
  end

  describe "validations" do
    it "is valid with valid attributes" do
      expect(amenity).to be_valid
    end

    it "is not valid without a name" do
      amenity.name = "  "
      expect(amenity).to_not be_valid
    end

    it "is not valid with a negative price" do
      amenity.price = -1.0
      expect(amenity).to_not be_valid

      amenity.price = 0
      expect(amenity).to be_valid

      amenity.membership_price = -1.0
      expect(amenity).to_not be_valid

      amenity.membership_price = 0
      expect(amenity).to be_valid
    end

    it "is not valid without a room" do
      amenity.room = nil
      expect(amenity).to_not be_valid
    end
  end

  describe "price handling" do
    it "sets price to zero if blank" do
      amenity.price = nil
      expect(amenity.price).to eq(0)

      amenity.membership_price = nil
      expect(amenity.price).to eq(0)
    end
  end

  describe "feature vs add-on (derived from rate)" do
    let(:room) { create(:room) }

    it "is a feature when both rates are zero" do
      a = create(:amenity, room: room, name: "Whiteboard", price: 0, membership_price: 0)
      expect(a.feature?).to be(true)
      expect(a.orderable?).to be(false)
    end

    it "is an orderable add-on when any rate is positive" do
      paid = create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)
      free_for_members = create(:amenity, room: room, name: "Parking", price: 20, membership_price: 0)
      expect(paid.orderable?).to be(true)
      expect(free_for_members.orderable?).to be(true)
      expect(paid.feature?).to be(false)
    end

    it "scopes partition the association" do
      create(:amenity, room: room, name: "Monitor", price: 0, membership_price: 0)
      create(:amenity, room: room, name: "Catering", price: 50, membership_price: 35)
      expect(room.amenities.features.pluck(:name)).to eq(["Monitor"])
      expect(room.amenities.add_ons.pluck(:name)).to eq(["Catering"])
    end
  end
end
