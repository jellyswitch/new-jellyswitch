class AddNotifiedAtToReservations < ActiveRecord::Migration[7.2]
  # Phase 6 review fix: per-channel idempotency markers for the booker arrival
  # and started pushes. Edits re-run the reminder scheduler WITHOUT cancelling
  # the old jobs (the existing convention), so two jobs can target a still-valid
  # instant and both fire. Each job atomically claims its marker before sending
  # (UPDATE ... WHERE col IS NULL); a genuinely re-timed booking resets the
  # markers (UpdateRoomReservation) so it can notify once more. Additive/reversible.
  def change
    add_column :reservations, :arrival_notified_at, :datetime
    add_column :reservations, :started_notified_at, :datetime
  end
end
