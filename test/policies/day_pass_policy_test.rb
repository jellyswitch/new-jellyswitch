require "test_helper"

class DayPassPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_create
    assert_permit @admin, DayPass
  end
end