class CreateLeaseRenewalRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :lease_renewal_requests do |t|
      t.references :office_lease, null: false, foreign_key: true
      t.references :operator, null: false, foreign_key: true
      t.references :location, foreign_key: true

      t.integer :proposed_price_in_cents, null: false
      t.integer :current_price_in_cents, null: false
      t.date :proposed_start_date, null: false
      t.date :proposed_end_date, null: false
      t.string :escalation_applied
      t.string :status, null: false, default: "pending_leasee"
      t.text :leasee_notes
      t.text :admin_notes
      t.datetime :leasee_responded_at
      t.datetime :admin_responded_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :lease_renewal_requests, [:office_lease_id, :status]
  end
end
