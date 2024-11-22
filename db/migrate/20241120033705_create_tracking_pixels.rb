class CreateTrackingPixels < ActiveRecord::Migration[7.0]
  def change
    create_table :tracking_pixels do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.string :name
      t.string :script
      t.integer :position, default: 0, index: true

      t.timestamps
    end
  end
end
