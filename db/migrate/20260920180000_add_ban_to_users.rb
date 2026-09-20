# A ban is a stronger, sticky cousin of archive. Archive stays a soft delete
# that keeps every member ability (an archived account can still log in, buy
# a membership and come back). Banning is the operator saying "not welcome
# here": it archives + unapproves, suppresses marketing, and blocks purchases
# and in-app messaging. The marker lives on the user (not derived from
# archived) so a later Unarchive cannot quietly lift it — only Lift Ban does.
class AddBanToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :banned_at, :datetime
    add_column :users, :banned_by_id, :bigint
  end
end
