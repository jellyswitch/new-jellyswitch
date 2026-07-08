class AddAttendeeCountToReservations < ActiveRecord::Migration[7.1]
  # Optional attendee count a member can enter when booking a paid meeting room,
  # shown to admins in the activity feed. Nullable — the field is optional.
  def change
    add_column :reservations, :attendee_count, :integer
  end
end
