require "test_helper"

class AmenityTest < ActiveSupport::TestCase
  def setup
    @room = Room.create(name: "Test Room")
    @amenity = Amenity.new(name: "WiFi", price: 5.0, room: @room)
  end

  def teardown
    @room.destroy
    Amenity.destroy_all
  end

  test "associations" do
    assert_equal :has_and_belongs_to_many, Amenity.reflect_on_association(:reservations).macro
  end

  test "should be valid" do
    assert @amenity.valid?
  end

  test "name should be present" do
    @amenity.name = "  "
    assert_not @amenity.valid?
  end

  test "price should be greater than or equal to 0" do
    @amenity.price = -1.0
    assert_not @amenity.valid?

    @amenity.price = 0
    assert @amenity.valid?
  end

  test "set price to zero if blank" do
    @amenity.price = nil
    assert_equal 0, @amenity.price
  end

  test "should belong to a room" do
    @amenity.room = nil
    assert_not @amenity.valid?
  end
end
