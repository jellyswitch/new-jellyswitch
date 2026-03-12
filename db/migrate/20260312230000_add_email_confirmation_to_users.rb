class AddEmailConfirmationToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :email_confirmed, :boolean, default: false, null: false
    add_column :users, :confirmation_token, :string
    add_column :users, :confirmation_sent_at, :datetime

    # All existing users are considered confirmed
    reversible do |dir|
      dir.up do
        execute "UPDATE users SET email_confirmed = true"
      end
    end
  end
end
