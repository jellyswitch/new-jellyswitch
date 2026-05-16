require "test_helper"
require "rake"

class LocationsBackfillTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "locations:backfill_geocoding" }
    Rake::Task["locations:backfill_geocoding"].reenable
  end

  test "geocodes only locations with nil latitude that have an address" do
    has_geo  = locations(:cowork_tahoe_location)
    has_geo.update_columns(latitude: 1.0, longitude: 2.0, building_address: "1 Main St")

    needs_geo = Location.create!(operator: operators(:cowork_tahoe), name: "New")
    needs_geo.update_columns(latitude: nil, longitude: nil, building_address: "100 Test St")

    blank_addr = Location.create!(operator: operators(:cowork_tahoe), name: "Blank")
    blank_addr.update_columns(latitude: nil, longitude: nil, building_address: nil)

    fake_result_class = Struct.new(:latitude, :longitude) do
      def coordinates; [latitude, longitude]; end
    end
    fake_result = fake_result_class.new(50.0, -100.0)

    call_count = 0
    Geocoder.stub(:search, ->(*_args) { call_count += 1; [fake_result] }) do
      capture_io { Rake::Task["locations:backfill_geocoding"].invoke }
    end

    assert_equal 1.0,    has_geo.reload.latitude, "untouched (already had lat)"
    assert_equal 50.0,   needs_geo.reload.latitude, "backfilled"
    assert_nil           blank_addr.reload.latitude, "skipped (no address)"
    assert_equal 1,      call_count, "geocoder called once (only for needs_geo)"
  end
end
