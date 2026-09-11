require "test_helper"

class Embed::TourRequestsConversionTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(tour_widget_enabled: true)
    @location = @operator.locations.first
    @location.update!(visible: true)
    Rails.cache.clear
  end

  test "a tour request records a widget lead conversion tied to the activity" do
    assert_difference -> { Conversion.where(kind: "tour_request").count } => 1 do
      post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
        name: "Alex Tour", email: "alex+conv@example.com", phone: "555-1212",
        message: "Interested", location_id: @location.id,
      }
    end

    row = Conversion.where(kind: "tour_request").last
    activity = Activity.where(kind: "tour_request").last
    assert_equal activity, row.subject
    assert_equal "widget", row.surface
    assert_equal @location.id, row.location_id
    assert_equal User.find_by(email: "alex+conv@example.com"), row.user
    assert_equal "website", row.channel, "no referrer + widget surface = the operator's own website"
  end
end
