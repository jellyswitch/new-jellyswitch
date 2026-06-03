require "test_helper"

# Coverage for /api/v1/auth/operators — the public catalog endpoint that
# powers the signup-screen "Choose your space" picker on the React Native
# mobile app. Used to return every operator in the jellyswitch ecosystem
# with no scoping, which leaked cross-brand operators (Innogrove, InSpark,
# Studio) and any low-quality / spammy operator signups into branded apps'
# pickers. Now hard-scoped to the requesting X-Operator-Subdomain header.
class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    # Signup is Rack::Attack-throttled per IP (5/min). Tests share an IP, so
    # without a reset the accumulated counter trips 429s in unrelated signup
    # tests depending on run order. Start every test with a clean counter; the
    # throttle test deliberately fires its own burst.
    Rails.cache.clear
  end

  test "operators returns only the requesting brand when X-Operator-Subdomain is set" do
    get "/api/v1/auth/operators",
        headers: { "X-Operator-Subdomain" => @operator.subdomain }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["operators"].length
    assert_equal @operator.subdomain, body["operators"].first["subdomain"]
    assert_equal @operator.name,      body["operators"].first["name"]
  end

  test "operators returns an empty array when no subdomain header is sent" do
    get "/api/v1/auth/operators"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["operators"]
  end

  test "operators returns an empty array when the subdomain header is unknown" do
    get "/api/v1/auth/operators",
        headers: { "X-Operator-Subdomain" => "no-such-operator" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["operators"]
  end

  test "operators includes the visible locations for the requesting brand" do
    get "/api/v1/auth/operators",
        headers: { "X-Operator-Subdomain" => @operator.subdomain }

    body = JSON.parse(response.body)
    op = body["operators"].first
    assert op["locations"].is_a?(Array)
    refute op["locations"].empty?, "expected at least one visible location for #{@operator.subdomain}"
    op["locations"].each do |loc|
      assert loc["id"].present?
      assert loc["name"].present?
    end
  end

  # --- Turnstile bot protection on member signup (LENIENT rollout phase) ---
  #
  # The endpoint must stay backward-compatible: store builds in the wild don't
  # send a `cf-turnstile-response` token yet, and TURNSTILE_SECRET is set in
  # production, so a hard requirement would break every existing mobile signup.
  # Lenient contract: verify ONLY when a token is present; pass untokened
  # requests straight through. In the test env TURNSTILE_SECRET is unset, so the
  # Verifier short-circuits to success — to exercise the blocking path we stub
  # it. Mirrors test/controllers/onboarding_controller_test.rb.

  def signup_params(overrides = {})
    {
      subdomain: @operator.subdomain,
      name: "New Member",
      email: "new-member-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      phone: "5305551234",
    }.merge(overrides)
  end

  test "signup without a Turnstile token creates the account and never verifies (lenient)" do
    Turnstile::Verifier.expects(:call).never
    assert_difference -> { User.count }, 1 do
      post "/api/v1/auth/signup", params: signup_params
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert body["token"].present?
  end

  test "signup with a valid Turnstile token creates the account" do
    Turnstile::Verifier.stubs(:call).returns(
      Turnstile::Verifier::Result.new(success?: true, error_codes: [])
    )
    assert_difference -> { User.count }, 1 do
      post "/api/v1/auth/signup", params: signup_params("cf-turnstile-response" => "good-token")
    end
    assert_response :created
  end

  test "signup with a failing Turnstile token creates no account and returns 422" do
    Turnstile::Verifier.stubs(:call).returns(
      Turnstile::Verifier::Result.new(success?: false, error_codes: ["invalid-input-response"])
    )
    assert_no_difference -> { User.count } do
      post "/api/v1/auth/signup", params: signup_params("cf-turnstile-response" => "bad-token")
    end
    assert_response :unprocessable_entity
  end

  test "signup verifies with context mobile_signup when a token is present" do
    Turnstile::Verifier.expects(:call).with(
      has_entries(context: "mobile_signup", token: "some-token")
    ).returns(Turnstile::Verifier::Result.new(success?: true, error_codes: []))
    post "/api/v1/auth/signup", params: signup_params("cf-turnstile-response" => "some-token")
    assert_response :created
  end

  test "signup with a filled honeypot creates no account and never verifies" do
    Turnstile::Verifier.expects(:call).never
    assert_no_difference -> { User.count } do
      post "/api/v1/auth/signup", params: signup_params(_hp: "i am a bot")
    end
    assert_response :unprocessable_entity
  end

  test "signup throttles after 5 requests per minute per IP" do
    Rails.cache.clear

    6.times { post "/api/v1/auth/signup", params: signup_params }
    # 6th response should be 429 (Rack::Attack signup/ip throttle).
    assert_response :too_many_requests
  ensure
    Rails.cache.clear
  end

  # --- Location hardening ---
  # A member self-signup must never land on a hidden/orphan location.
  # Regression for the phantom "Cowork Tahoe " (loc 1627, visible=false) under
  # the Untethered operator, which stranded real signups on a deprecated space.

  test "signup ignores a hidden location_id and falls back to a visible location" do
    hidden = Location.create!(
      name:              "Hidden Signup Space",
      operator:          @operator,
      visible:           false,
      time_zone:         "Pacific Time (US & Canada)",
      working_day_start: "09:00",
      working_day_end:   "18:00",
    )
    visible = @operator.locations.visible.first

    assert_difference -> { User.count }, 1 do
      post "/api/v1/auth/signup", params: signup_params(location_id: hidden.id)
    end
    assert_response :created
    assert_equal visible.id, User.order(:created_at).last.original_location_id,
      "self-signup must not be assigned to a hidden location"
  end

  test "signup honors a valid visible location_id" do
    visible = @operator.locations.visible.first
    post "/api/v1/auth/signup", params: signup_params(location_id: visible.id)
    assert_response :created
    assert_equal visible.id, User.order(:created_at).last.original_location_id
  end
end
