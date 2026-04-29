class AddFeaturesToRooms < ActiveRecord::Migration[7.1]
  def change
    # Lightweight tag list ("AV", "Hybrid meeting compatible", "Extra
    # monitor", etc.). Distinct from the existing amenities model,
    # which carries pricing — features are free informational tags
    # admins set per room and members see on the booking screen.
    add_column :rooms, :features, :text, array: true, default: []
  end
end
