class AddDayOfficePassToReservations < ActiveRecord::Migration[7.2]
  def change
    # nullify: destroying a pass must never orphan-block a room; the model
    # releases the hold first (DayPass before_destroy), this is the backstop.
    # FK added NOT VALID (existing rows are all NULL anyway); validated in the
    # follow-up migration under a non-write-blocking lock.
    add_reference :reservations, :day_office_pass, index: true
    add_foreign_key :reservations, :day_passes, column: :day_office_pass_id,
                    on_delete: :nullify, validate: false
  end
end
