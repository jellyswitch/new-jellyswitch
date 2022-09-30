require "test_helper"

class FeedItemPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_questions
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_activity
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_notes
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_financial
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_create
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_show
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end

  def test_destroy
    assert_not_permitted @member, FeedItem
    assert_permit @admin, FeedItem
    assert_permit @community_manager, FeedItem
    assert_permit @general_manager, FeedItem
  end
end