class CreateConversions < ActiveRecord::Migration[7.2]
  # Server-side conversion log (David, 2026-09-11). Purchases already push a
  # `purchase` dataLayer event for Google Ads, but nothing is stored on our
  # side, so Jellyswitch itself can't report signups → purchases by channel.
  # One row per conversion (signup, lead, purchase), snapshotting the person's
  # first-touch attribution at the moment it happened.
  def change
    create_table :conversions do |t|
      t.references :operator, null: false, index: false
      t.references :location, index: false
      t.references :user, index: true
      t.string  :kind, null: false
      t.string  :subject_type
      t.bigint  :subject_id
      t.integer :amount_cents, default: 0, null: false
      t.string  :surface            # web | app | widget | admin | backfill
      t.boolean :self_serve, default: true, null: false
      t.bigint  :actor_id           # staff member who performed it, if any
      t.bigint  :ahoy_visit_id
      t.string  :channel            # first-touch channel snapshot
      t.string  :source
      t.string  :medium
      t.string  :campaign
      t.string  :referrer_domain
      t.string  :landing_page
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :conversions, [:operator_id, :occurred_at]
    add_index :conversions, [:location_id, :occurred_at]
    add_index :conversions, [:subject_type, :subject_id, :kind], unique: true,
              name: "index_conversions_on_subject_and_kind"
    add_index :conversions, :kind
  end
end
