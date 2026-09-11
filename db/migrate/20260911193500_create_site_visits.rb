class CreateSiteVisits < ActiveRecord::Migration[7.2]
  # Marketing-site sessions reported by the concierge launcher's page-view
  # beacon (David, 2026-09-11: "data one step before the referral site").
  # One row per visitor session (4h window), classified into a channel at
  # the moment it starts. No IP, no PII — a random per-browser visitor id.
  def change
    create_table :site_visits do |t|
      t.references :operator, null: false, index: false
      t.string  :visitor_id, null: false
      t.string  :host
      t.string  :landing_page
      t.string  :referrer
      t.string  :referring_domain
      t.string  :utm_source
      t.string  :utm_medium
      t.string  :utm_campaign
      t.string  :utm_term
      t.string  :utm_content
      t.string  :channel
      t.string  :source
      t.integer :page_views, default: 1, null: false
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.string  :user_agent
      t.timestamps
    end
    add_index :site_visits, [:operator_id, :started_at]
    add_index :site_visits, [:operator_id, :visitor_id, :last_seen_at]
  end
end
