require "test_helper"

class LocationGeocodingTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  FakeGeoResult = Struct.new(:latitude, :longitude) do
    def coordinates
      [latitude, longitude]
    end
  end

  test "geocodes when address fields change and address is present" do
    @location.latitude = nil
    @location.longitude = nil

    fake_result = FakeGeoResult.new(38.9399, -119.9772)
    Geocoder.stub(:search, ->(*_args) { [fake_result] }) do
      @location.building_address = "1 Main St"
      @location.save!
    end

    assert_in_delta 38.9399,  @location.reload.latitude,  0.001
    assert_in_delta -119.9772, @location.longitude, 0.001
  end

  test "does NOT geocode when address fields unchanged" do
    fake_result = FakeGeoResult.new(1.0, 2.0)
    Geocoder.stub(:search, ->(*_args) { [fake_result] }) do
      @location.update!(latitude: 1.0, longitude: 2.0, building_address: "1 Main St")
    end

    Geocoder.stub(:search, ->(*_) { raise "should not be called" }) do
      @location.name = "Renamed (not an address change)"
      @location.save!
    end

    assert_equal 1.0, @location.reload.latitude
  end

  test "does NOT geocode when address is blank" do
    @location.building_address = nil
    @location.latitude = nil

    Geocoder.stub(:search, ->(*_) { raise "should not be called" }) do
      @location.city = "Anywhere"
      @location.save!
    end

    assert_nil @location.reload.latitude
  end

  test "#address_string joins available fields with commas" do
    @location.assign_attributes(building_address: "1 Main St", city: "Tahoe", state: "CA", zip: "96150")
    assert_equal "1 Main St, Tahoe, CA, 96150", @location.address_string
  end
end
