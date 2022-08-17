require 'test_helper'

class FeedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    log_in @user
  end

  test "should render :index without errors" do
    get feed_items_path
    assert_response :success
  end
end
