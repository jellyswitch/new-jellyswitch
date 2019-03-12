# == Schema Information
#
# Table name: feed_item_comments
#
#  id           :bigint(8)        not null, primary key
#  comment      :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  feed_item_id :integer          not null
#  user_id      :integer          not null
#

require 'test_helper'

class FeedItemCommentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
