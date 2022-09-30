require "test_helper"

class OnboardingPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_show
    assert_not_permitted @member, :onboarding
    assert_permit @admin, :onboarding
    assert_permit @community_manager, :onboarding
    assert_permit @general_manager, :onboarding
    assert_permit @superadmin, :onboarding
  end
end