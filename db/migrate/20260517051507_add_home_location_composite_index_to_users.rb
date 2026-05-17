class AddHomeLocationCompositeIndexToUsers < ActiveRecord::Migration[7.1]
  def change
    add_index :users,
              [:operator_id, :home_state, :home_city],
              name: "index_users_on_operator_home_state_home_city"
  end
end
