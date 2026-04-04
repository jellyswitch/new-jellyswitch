class CreateAutomatedWorkflows < ActiveRecord::Migration[7.1]
  def change
    create_table :automated_workflows do |t|
      t.references :operator, null: false
      t.references :location
      t.string :workflow_type, null: false
      t.boolean :enabled, null: false, default: false
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :automated_workflows, [:operator_id, :location_id, :workflow_type], unique: true, name: "idx_workflows_operator_location_type"
  end
end
