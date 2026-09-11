require "test_helper"

# Mobile signups write a server-side Conversion (kind signup, surface app)
# so the Conversions report can count them by channel.
class Api::V1::AuthSignupConversionTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(approval_required: false)
    Rails.cache.clear
  end

  test "signup records a self-serve app conversion credited to the app channel" do
    assert_difference -> { Conversion.where(kind: "signup").count } => 1 do
      post "/api/v1/auth/signup",
           params: { subdomain: @operator.subdomain, name: "App Signup", email: "app.signup@example.com",
                     password: "Password123!", phone: "5305550101", terms_accepted: true },
           as: :json
    end
    assert_response :created

    user = User.find_by(email: "app.signup@example.com")
    row = Conversion.find_by(kind: "signup", subject: user)
    assert_equal "app", row.surface
    assert row.self_serve
    assert_equal "app", row.channel
    assert_equal "app", user.reload.acquisition_channel
  end
end
