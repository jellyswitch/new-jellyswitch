# "Access only" people — couriers, cleaning staff, etc. They can unlock their
# home space's doors 24/7 but are NOT members: hidden from member lists,
# counts and marketing (User.excluding_access_only).
class AddAccessOnlyToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :access_only, :boolean, default: false, null: false
  end
end
