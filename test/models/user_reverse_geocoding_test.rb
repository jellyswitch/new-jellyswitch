require "test_helper"

class UserReverseGeocodingTest < ActiveSupport::TestCase
  setup do
    # Use any user fixture — pick one and stick with it.
    @user = User.where.not(operator_id: nil).first || users.first
  end

  test "fills home_city and home_state when lat/lng set" do
    fake_place = Struct.new(:city, :state_code).new("South Lake Tahoe", "CA")

    Geocoder.stub(:search, ->(*_args) { [fake_place] }) do
      @user.home_latitude = 38.9399
      @user.home_longitude = -119.9772
      @user.save!
    end

    @user.reload
    assert_equal "South Lake Tahoe", @user.home_city
    assert_equal "CA",               @user.home_state
  end

  test "does NOT reverse-geocode when lat/lng unchanged" do
    Geocoder.stub(:search, ->(*_args) { [Struct.new(:city, :state_code).new("Tahoe", "CA")] }) do
      @user.update!(home_latitude: 38.9399, home_longitude: -119.9772)
    end

    Geocoder.stub(:search, ->(*_args) { raise "should not be called" }) do
      @user.name = "Renamed (not a coord change)"
      @user.save!
    end

    assert_equal "Tahoe", @user.reload.home_city
  end

  test "tolerates empty reverse-geocode results without raising" do
    Geocoder.stub(:search, ->(*_args) { [] }) do
      @user.home_latitude = 1.0
      @user.home_longitude = 1.0
      assert_nothing_raised { @user.save! }
    end

    @user.reload
    assert_nil @user.home_city
    assert_nil @user.home_state
  end
end
