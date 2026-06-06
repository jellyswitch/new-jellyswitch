class CreateOfficerndImports < ActiveRecord::Migration[7.2]
  def change
    create_table :officernd_imports do |t|
      t.bigint :operator_id, null: false
      t.bigint :location_id
      t.bigint :created_by_id
      t.string :kind, null: false, default: "members"      # members | invoices
      t.string :status, null: false, default: "pending"    # pending | previewed | committed | failed
      t.string :amount_format, null: false, default: "dollars"
      t.jsonb :headers, null: false, default: []
      t.jsonb :column_mapping, null: false, default: {}
      t.jsonb :plan_mapping, null: false, default: {}
      t.integer :row_count, null: false, default: 0
      t.jsonb :result_log, null: false, default: {}

      t.timestamps
    end

    add_index :officernd_imports, :operator_id
    add_index :officernd_imports, :location_id
  end
end
