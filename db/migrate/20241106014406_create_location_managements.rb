class CreateLocationManagements < ActiveRecord::Migration[7.0]
  def change
    create_table :location_managements do |t|
      t.references :location, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
