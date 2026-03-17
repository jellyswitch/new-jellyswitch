class AddLocationIdToProductEmailTemplates < ActiveRecord::Migration[7.0]
  def change
    add_reference :product_email_templates, :location, foreign_key: true, null: true
    remove_index :product_email_templates, [:operator_id, :product_type, :email_type]
    add_index :product_email_templates, [:operator_id, :location_id, :product_type, :email_type],
              unique: true, name: 'idx_pet_operator_location_product_email'
  end
end
