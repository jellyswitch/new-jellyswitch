class AddResumesAtToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :resumes_at, :datetime
  end
end
