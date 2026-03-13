class CreateProductEmailTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :product_email_templates do |t|
      t.references :operator, null: false, foreign_key: true
      t.string :product_type, null: false
      t.string :email_type, null: false
      t.string :subject, null: false
      t.boolean :enabled, default: false
      t.integer :follow_up_delay_days

      t.timestamps
    end

    add_index :product_email_templates, [:operator_id, :product_type, :email_type], unique: true, name: 'idx_product_email_templates_unique'
  end
end
