class AddBuildingAccessWindowMinutesToOperators < ActiveRecord::Migration[7.2]
  # Phase 4 of the reservation billing redesign (ADR 0013): a reservation grants
  # building access only within a time window around its slot — from this many
  # minutes before start to the same number after end (default 60), instead of
  # the old all-day grant. The door and the (Phase 6) "come back soon" push read
  # this one column so the promise can never drift from the door. Additive +
  # reversible.
  def change
    add_column :operators, :building_access_window_minutes, :integer, null: false, default: 60
  end
end
