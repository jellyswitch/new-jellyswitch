class AddUniqueIndexOnUsersOperatorIdAndLowerEmail < ActiveRecord::Migration[7.2]
  def change
    # DB backstop for the case-insensitive email uniqueness validation
    # (see User): validation-skipping saves and concurrent requests can no
    # longer mint duplicate member accounts. Existing duplicates were cleaned
    # up in prod before this ships. The expression also matches the login
    # lookup (WHERE operator_id = ? AND lower(email) = ?), which previously
    # had no index at all.
    add_index :users, "operator_id, lower(email)",
              unique: true,
              name: "index_users_on_operator_id_and_lower_email"
  end
end
