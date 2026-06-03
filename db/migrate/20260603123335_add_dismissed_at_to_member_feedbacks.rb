class AddDismissedAtToMemberFeedbacks < ActiveRecord::Migration[7.2]
  def change
    add_column :member_feedbacks, :dismissed_at, :datetime
  end
end
