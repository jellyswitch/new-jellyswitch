require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  # Signup lives under the `app` subdomain constraint (config/routes.rb).
  setup { host! "app.example.com" }

  # These cover the bot-protection added to the public operator signup form.
  # In the test env TURNSTILE_SECRET is unset, so the Verifier short-circuits to
  # success — to exercise the blocking path we stub it to fail.

  test "create_user with a filled honeypot creates no account and never verifies" do
    Turnstile::Verifier.expects(:call).never
    assert_no_difference -> { User.count } do
      post create_user_onboarding_index_path,
        params: {
          email: "bot@example.com",
          password: "password123",
          password_confirmation: "password123",
          _hp: "i am a bot",
        },
        env: default_env
    end
  end

  test "create_user with a failing Turnstile creates no account and flashes an error" do
    Turnstile::Verifier.stubs(:call).returns(
      Turnstile::Verifier::Result.new(success?: false, error_codes: ["invalid-input-response"])
    )
    assert_no_difference -> { User.count } do
      post create_user_onboarding_index_path,
        params: {
          email: "bot@example.com",
          password: "password123",
          password_confirmation: "password123",
        },
        env: default_env
    end
    assert_equal "Please complete the captcha and try again.", flash[:error]
  end
end
