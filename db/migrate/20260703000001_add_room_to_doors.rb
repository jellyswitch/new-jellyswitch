class AddRoomToDoors < ActiveRecord::Migration[7.2]
  def change
    # ADR 0021: a Door attached to a Room IS that Room's lock — the
    # attachment is the classification (no door-type enum).
    add_reference :doors, :room, null: true, foreign_key: true, index: true
  end
end
