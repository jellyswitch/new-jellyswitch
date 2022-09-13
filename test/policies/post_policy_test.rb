require "test_helper"

class PostPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_permit @member, Post
    assert_permit @admin, Post
    assert_permit @general_manager, Post
    assert_permit @community_manager, Post
  end

  def test_new
    assert_permit @member, Post
    assert_permit @admin, Post
    assert_permit @general_manager, Post
    assert_permit @community_manager, Post
  end

  def test_create
    assert_permit @member, Post
    assert_permit @admin, Post
    assert_permit @general_manager, Post
    assert_permit @community_manager, Post
  end

  def test_show
    assert_permit @member, Post
    assert_permit @admin, Post
    assert_permit @general_manager, Post
    assert_permit @community_manager, Post
  end
end