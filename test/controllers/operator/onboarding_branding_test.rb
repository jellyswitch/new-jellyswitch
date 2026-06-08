require "test_helper"

class Operator::OnboardingBrandingTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
  end

  test "branding step saves brand colors and app icon" do
    log_in @admin
    patch create_branding_operator_onboarding_index_path,
      params: {
        operator: {
          primary_color: "#123456",
          accent_color: "#654321",
          app_icon_image: fixture_file_upload("app_icon.png", "image/png")
        }
      },
      env: default_env

    @operator.reload
    assert_equal "#123456", @operator.primary_color
    assert_equal "#654321", @operator.accent_color
    assert @operator.app_icon_image.attached?
  end

  test "branding page renders with the new fields" do
    log_in @admin
    get new_branding_operator_onboarding_index_path, env: default_env
    assert_response :success
    assert_select "input[name=?]", "operator[primary_color]"
    assert_select "input[name=?]", "operator[app_icon_image]"
  end
end
