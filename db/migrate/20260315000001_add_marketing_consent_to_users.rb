class AddMarketingConsentToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :marketing_consent, :boolean, default: false, null: false
  end
end
