class AddReservationToDayPasses < ActiveRecord::Migration[7.2]
  def change
    add_reference :day_passes, :reservation, null: true, foreign_key: { on_delete: :nullify }, index: true
  end
end
