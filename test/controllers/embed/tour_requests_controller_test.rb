require 'test_helper'

class Embed::TourRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(tour_widget_enabled: true)
    @location = @operator.locations.first
    @location.update!(visible: true)
  end

  test "GET show renders form when widget enabled" do
    get embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_response :success
    assert_select "form[action=?][method=?]",
                  embed_tour_request_path(operator_subdomain: @operator.subdomain), "post"
    assert_select "input[name=email]"
    assert_select "input[name=_hp]"
  end

  test "GET show 404s when widget disabled" do
    @operator.update!(tour_widget_enabled: false)
    get embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_response :not_found
  end

  test "GET show 404s when subdomain unknown" do
    get embed_tour_request_path(operator_subdomain: "no-such-operator")
    assert_response :not_found
  end

  test "GET show with pinned location hides the picker and pre-selects" do
    get embed_tour_request_for_location_path(operator_subdomain: @operator.subdomain, location_id: @location.id)
    assert_response :success
    assert_select "input[type=hidden][name=location_id][value=?]", @location.id.to_s
  end

  test "GET show sets X-Frame-Options ALLOWALL" do
    get embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_equal "ALLOWALL", response.headers["X-Frame-Options"]
  end
end
