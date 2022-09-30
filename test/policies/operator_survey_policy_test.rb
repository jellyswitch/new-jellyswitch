require "test_helper"

class OperatorSurveyPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_new
    assert_not_permitted @member, OperatorSurvey
    assert_not_permitted @community_manager, OperatorSurvey
    assert_not_permitted @general_manager, OperatorSurvey
    assert_permit @admin, OperatorSurvey
  end

  def test_create
    assert_not_permitted @member, OperatorSurvey
    assert_not_permitted @community_manager, OperatorSurvey
    assert_not_permitted @general_manager, OperatorSurvey
    assert_permit @admin, OperatorSurvey
  end

  def test_index
    assert_not_permitted @member, OperatorSurvey
    assert_not_permitted @community_manager, OperatorSurvey
    assert_not_permitted @general_manager, OperatorSurvey
    assert_not_permitted @admin, OperatorSurvey
    assert_permit @superadmin, OperatorSurvey
  end

  def test_show
    assert_not_permitted @member, OperatorSurvey
    assert_not_permitted @community_manager, OperatorSurvey
    assert_not_permitted @general_manager, OperatorSurvey
    assert_not_permitted @admin, OperatorSurvey
    assert_permit @superadmin, OperatorSurvey
  end

  def test_wait
    assert_not_permitted @member, OperatorSurvey
    assert_not_permitted @community_manager, OperatorSurvey
    assert_not_permitted @general_manager, OperatorSurvey
    assert_permit @admin, OperatorSurvey
  end
end