class AddLastReadAtToMemberFeedbacks < ActiveRecord::Migration[7.1]
  def change
    add_column :member_feedbacks, :last_read_at, :datetime
  end
end
