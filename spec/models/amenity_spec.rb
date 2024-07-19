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
end
