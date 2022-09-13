require "test_helper"

class EventPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_new
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_create
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_edit
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_update
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_destroy
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end
end