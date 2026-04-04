class AddEmailFieldsToUsersAndOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :email_opted_out, :boolean, null: false, default: false
    add_column :users, :email_bounced, :boolean, null: false, default: false

    add_column :operators, :mailchimp_api_key, :string
    add_column :operators, :mailchimp_audience_id, :string
  end
end
