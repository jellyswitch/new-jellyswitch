class AddAlwaysOnToTrackingPixels < ActiveRecord::Migration[7.1]
  def change
    add_column :tracking_pixels, :always_on, :boolean, default: false, null: false
  end
end
