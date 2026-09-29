require 'test_helper'

class FeedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_admin)
    log_in @user
  end

  test "should render :index without errors" do
    get feed_items_path, env: default_env
    assert_response :success
  end

  test "renders an office_lease_created card on the web feed" do
    FeedItem.create!(
      operator: @user.operator, location: @user.original_location, user: @user,
      blob: { "type" => "office_lease_created", "text" => "Scott Lowe leased Office 300 · $698.98/mo" },
    )
    get feed_items_path, env: default_env
    assert_response :success
    assert_includes response.body, "leased an office"
    assert_includes response.body, "Scott Lowe leased Office 300 · $698.98/mo"
  end

  test "should create a new feed item and redirect back to index (web)" do
    post feed_items_path( params: { feed_item: { text: "This is a management note" } }), env: default_env
    assert_redirected_to controller: "operator/feed_items", action: "index"
    assert FeedItem.last.location = locations(:cowork_tahoe_location)
  end

  test "should create a new feed item and redirect back to index (iOS)" do
    post feed_items_path( params: { feed_item: { text: "This is a management note" } }), env: ios_env
    assert_redirected_to controller: "operator/feed_items", action: "index"
    assert FeedItem.last.location = locations(:cowork_tahoe_location)
  end

  test "should create membership updated feed item and redirect back to index (web)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "membership_updated", text: "user updated their membership" } }, env: default_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create membership updated feed item and redirect back to index (ios)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "membership_updated", text: "user updated their membership" } }, env: ios_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create membership cancelled feed item and redirect back to index (web)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "membership_cancelled", text: "user cancelled their membership" } }, env: default_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create membership cancelled feed item and redirect back to index (ios)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "membership_cancelled", text: "user cancelled their membership" } }, env: ios_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create announcement feed item and redirect back to index (web)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "announcement", text: "this is an announcement" } }, env: default_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create announcement feed item and redirect back to index (ios)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "announcement", text: "this is an announcement" } }, env: ios_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create account deleted feed item and redirect back to index (web)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "account_deletion", text: "user deleted their account" } }, env: default_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create account deleted feed item and redirect back to index (ios)" do
    assert_difference("FeedItem.count") do
      post feed_items_url, params: { feed_item: { type: "account_deletion", text: "user deleted their account" } }, env: ios_env
    end

    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

end
