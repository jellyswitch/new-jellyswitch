require 'test_helper'

class Embed::TourRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(tour_widget_enabled: true)
    @location = @operator.locations.first
    @location.update!(visible: true)
    Rails.cache.clear
  end

  test "GET show renders form when widget enabled" do
    get embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_response :success
    assert_select "form[action=?][method=?]",
                  embed_tour_request_path(operator_subdomain: @operator.subdomain), "post"
    assert_select "input[name=email]"
    assert_select "input[name=_hp]"
  end

  test "GET show includes the iframe auto-height script" do
    get embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_response :success
    assert_includes @response.body, "jswEmbedHeight"
  end

  test "GET show 404s when widget disabled" do
    @operator.update!(tour_widget_enabled: false)
    get embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_response :not_found
  end

  test "GET show with a valid preview token renders form even when widget disabled" do
    # Regression: admins on the settings page need the live preview iframe to
    # render even when tour_widget_enabled is off, otherwise the preview is
    # blank exactly when they want to look at it. The settings view signs a
    # short-lived token that proves the iframe is coming from a logged-in
    # operator admin; the embed controller verifies it without depending on
    # session cookies traversing the embed boundary.
    @operator.update!(tour_widget_enabled: false)
    token = Embed::TourRequestsController.verifier.generate({
      "operator_id" => @operator.id, "exp" => 1.hour.from_now.to_i,
    })

    get embed_tour_request_path(operator_subdomain: @operator.subdomain, preview_token: token)

    assert_response :success
    assert_select "form[action=?]", embed_tour_request_path(operator_subdomain: @operator.subdomain)
    assert_select "div", text: /Preview mode/
  end

  test "GET show with an expired preview token still 404s when widget disabled" do
    @operator.update!(tour_widget_enabled: false)
    token = Embed::TourRequestsController.verifier.generate({
      "operator_id" => @operator.id, "exp" => 1.hour.ago.to_i,
    })

    get embed_tour_request_path(operator_subdomain: @operator.subdomain, preview_token: token)
    assert_response :not_found
  end

  test "GET show with a preview token for a different operator still 404s" do
    @operator.update!(tour_widget_enabled: false)
    token = Embed::TourRequestsController.verifier.generate({
      "operator_id" => @operator.id + 9999, "exp" => 1.hour.from_now.to_i,
    })

    get embed_tour_request_path(operator_subdomain: @operator.subdomain, preview_token: token)
    assert_response :not_found
  end

  test "GET show with a tampered preview token still 404s" do
    @operator.update!(tour_widget_enabled: false)

    get embed_tour_request_path(operator_subdomain: @operator.subdomain, preview_token: "not-a-real-token")
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
        preferred_time: "Weekday mornings",
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
    assert_equal "Weekday mornings", activity.payload["preferred_time"]
    assert_equal "widget", activity.payload["source"]

    assert_redirected_to embed_tour_request_thank_you_path(operator_subdomain: @operator.subdomain)
  end

  test "POST create at Untethered's Zephyr Cove location also logs a tour request at Cowork Tahoe" do
    untethered = Operator.create!(name: "Untethered", subdomain: "untethered", tour_widget_enabled: true)
    zephyr = ActsAsTenant.with_tenant(untethered) do
      untethered.locations.create!(name: "Untethered - Lake Tahoe, NV", city: "Zephyr Cove", visible: true)
    end

    assert_difference -> { User.where(operator: untethered).count } => 1,
                      -> { User.where(operator: @operator).count } => 1,
                      -> { Activity.where(kind: "tour_request").count } => 2 do
      post embed_tour_request_path(operator_subdomain: "untethered"), params: {
        name: "Tahoe Prospect", email: "tahoe+prospect@example.com", phone: "555-0100",
        message: "Curious about both spaces", location_id: zephyr.id,
      }
    end
    assert_redirected_to embed_tour_request_thank_you_path(operator_subdomain: "untethered")

    source = Activity.where(kind: "tour_request", operator: untethered).last
    mirror = Activity.where(kind: "tour_request", operator: @operator).last
    assert_equal zephyr.id, source.subject_id
    assert_equal @location.id, mirror.subject_id
    assert_equal "Curious about both spaces", mirror.payload["message"]
    assert_equal source.id, mirror.payload.dig("mirrored_from", "activity_id")
    assert_equal mirror.id, source.payload.dig("mirrored_to", "activity_id")
    assert_equal "tahoe+prospect@example.com", mirror.user.email
    assert_equal @operator.id, mirror.user.operator_id

    # One staff alert (for the Untethered activity), none for the mirror.
    assert_enqueued_with(job: SendNotificationsJob, args: [source, "TourRequestAlert"])
    tour_alerts = enqueued_jobs.select { |j| j["job_class"] == "SendNotificationsJob" && j["arguments"].last == "TourRequestAlert" }
    assert_equal 1, tour_alerts.size
  end

  test "POST create at Cowork Tahoe does not mirror anywhere" do
    assert_difference -> { Activity.where(kind: "tour_request").count } => 1 do
      post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
        name: "Local", email: "local@example.com", location_id: @location.id,
      }
    end
    assert_nil Activity.where(kind: "tour_request").last.payload["mirrored_to"]
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

  test "POST with honeypot filled silently returns 200 and writes nothing" do
    assert_no_difference -> { User.count } do
      assert_no_difference -> { Activity.count } do
        post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
          name: "Bot", email: "bot@spam.example", location_id: @location.id, _hp: "filled-by-bot",
        }
      end
    end
    assert_response :success
  end

  test "POST with failing Turnstile returns 422 and writes nothing" do
    original_secret = ENV["TURNSTILE_SECRET"]
    ENV["TURNSTILE_SECRET"] = "stub-secret"

    Turnstile::Verifier.stubs(:call).returns(
      Turnstile::Verifier::Result.new(success?: false, error_codes: ["invalid"])
    )

    assert_no_difference -> { Activity.count } do
      post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
        name: "Carl", email: "carl@example.com", location_id: @location.id,
        "cf-turnstile-response" => "bad",
      }
    end
    assert_response :unprocessable_entity
  ensure
    ENV["TURNSTILE_SECRET"] = original_secret
  end

  test "POST throttles after 5 requests per minute per IP" do
    Rails.cache.clear

    # Rack::Attack's throttle is a FIXED 1-minute window derived from Time.now.
    # Freeze time so all 6 requests fall in the same window -- otherwise a burst
    # that happens to straddle a minute boundary resets the counter mid-burst and
    # the 6th request comes back 303 instead of 429 (the source of this test's
    # intermittent CI failures).
    freeze_time do
      6.times do |i|
        post embed_tour_request_path(operator_subdomain: @operator.subdomain), params: {
          name: "Rate#{i}", email: "rate#{i}@example.com", location_id: @location.id,
        }
      end
    end
    # 6th response should be 429.
    assert_response :too_many_requests
  ensure
    Rails.cache.clear
  end
end
