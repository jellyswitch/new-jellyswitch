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

  test "POST create with valid params creates a new User and tour_request Activity" do
    assert_difference -> { User.count } => 1,
                      -> { Activity.where(kind: "tour_request").count } => 1 do
      post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
        name: "Alex Tour",
        email: "alex+tour@example.com",
        phone: "555-1212",
        message: "Interested in a hot desk",
        location_id: @location.id,
      }
    end

    user = User.find_by(email: "alex+tour@example.com")
    assert_equal "Alex Tour", user.name
    assert_equal @operator.id, user.operator_id
    assert_equal @location.id, user.original_location_id

    activity = Activity.where(kind: "tour_request").last
    assert_equal user.id, activity.user_id
    assert_equal @operator.id, activity.operator_id
    assert_equal @location.id, activity.subject_id
    assert_equal "Location", activity.subject_type
    assert_equal "Interested in a hot desk", activity.payload["message"]
    assert_equal "widget", activity.payload["source"]

    assert_redirected_to embed_tour_request_thank_you_path(operator_subdomain: @operator.subdomain)
  end

  test "POST create with existing email reuses the User and still logs Activity" do
    existing = User.create!(
      email: "existing+tour@example.com", name: "Existing", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!",
    )

    assert_difference -> { User.count } => 0,
                      -> { Activity.where(kind: "tour_request", user: existing).count } => 1 do
      post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
        name: "Existing", email: "existing+tour@example.com", location_id: @location.id,
      }
    end
  end

  test "POST create redirects to operator-configured thank-you URL if set" do
    @operator.update!(tour_widget_thank_you_url: "https://example.com/thanks")
    post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
      name: "Bea", email: "bea@example.com", location_id: @location.id,
    }
    assert_redirected_to "https://example.com/thanks"
  end

  test "POST with missing email returns 422" do
    post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
      name: "No Email", location_id: @location.id,
    }
    assert_response :unprocessable_entity
  end
end
