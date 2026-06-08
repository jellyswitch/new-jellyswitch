require "test_helper"

class Operator::OnboardingRequestMobileAppTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    @operator.update!(snippet: "A real space", primary_color: "#76B82A", accent_color: "#E8871E")
    @operator.logo_image.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")), filename: "l.png", content_type: "image/png")
    @operator.terms_of_service.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")), filename: "t.pdf", content_type: "application/pdf")
    @operator.app_icon_image.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")), filename: "i.png", content_type: "image/png")
  end

  test "enqueues the scaffold job and stamps the operator" do
    log_in @admin
    assert_enqueued_with(job: MobileApp::RequestScaffoldJob) do
      post request_mobile_app_operator_onboarding_index_path, env: default_env
    end
    assert @operator.reload.mobile_app_requested_at.present?
  end

  test "does not enqueue twice (idempotent)" do
    @operator.update!(mobile_app_requested_at: Time.current)
    log_in @admin
    assert_no_enqueued_jobs only: MobileApp::RequestScaffoldJob do
      post request_mobile_app_operator_onboarding_index_path, env: default_env
    end
  end
end
