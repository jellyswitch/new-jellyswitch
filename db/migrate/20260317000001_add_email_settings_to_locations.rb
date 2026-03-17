class AddEmailSettingsToLocations < ActiveRecord::Migration[7.0]
  def change
    add_column :locations, :sender_email, :string
    add_column :locations, :google_reviews_url, :string
    add_column :locations, :renewal_reminder_days, :integer
  end
end
