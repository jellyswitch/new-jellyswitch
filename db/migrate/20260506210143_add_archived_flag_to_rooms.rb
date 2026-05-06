class AddArchivedFlagToRooms < ActiveRecord::Migration[7.1]
  def change
    # Soft-delete flag — preserves historical reservations + invoices
    # that reference the room while removing it from active admin and
    # member lists. Distinct from `visible`: visible=false hides from
    # members but keeps it bookable by admins; archived=true hides it
    # from both unless the admin explicitly asks for archived rooms.
    add_column :rooms, :archived, :boolean, default: false, null: false
    add_index :rooms, :archived
  end
end
