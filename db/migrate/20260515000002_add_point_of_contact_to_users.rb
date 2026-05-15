class AddPointOfContactToUsers < ActiveRecord::Migration[7.0]
  def change
    add_reference :users, :point_of_contact, foreign_key: { to_table: :users }, null: true, index: true
  end
end
