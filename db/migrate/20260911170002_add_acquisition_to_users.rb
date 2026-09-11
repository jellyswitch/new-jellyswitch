class AddAcquisitionToUsers < ActiveRecord::Migration[7.2]
  # First-touch attribution per person, computed once from their earliest
  # Ahoy visit (same visitor cookie) and frozen. Conversions snapshot these.
  def change
    add_column :users, :acquisition_channel, :string
    add_column :users, :acquisition_source, :string
    add_column :users, :acquisition_medium, :string
    add_column :users, :acquisition_campaign, :string
    add_column :users, :acquisition_referrer, :string
    add_column :users, :acquisition_landing_page, :string
    add_column :users, :acquisition_visit_id, :bigint
    add_column :users, :acquired_at, :datetime

    add_index :users, [:operator_id, :acquisition_channel]
    # Backfill + first-touch lookup walk visits by the persistent visitor cookie.
    add_index :ahoy_visits, :visitor_token
  end
end
