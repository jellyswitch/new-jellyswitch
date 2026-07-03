class AddIncludeWithDayPassToRooms < ActiveRecord::Migration[7.2]
  # Phase 1 of the reservation billing redesign (ADR 0012): whether a room
  # counts toward the day-pass included-minutes bucket becomes an explicit
  # per-room boolean instead of being inferred from hourly_rate_in_cents == 0.
  # Default false; backfill true for every $0 (call) room so today's behavior
  # is preserved exactly. Operators toggle it per room in the room editor.
  #
  # Additive + reversible.
  def up
    add_column :rooms, :include_with_day_pass, :boolean, null: false, default: false

    execute(<<~SQL)
      UPDATE rooms
      SET include_with_day_pass = true
      WHERE hourly_rate_in_cents = 0 OR hourly_rate_in_cents IS NULL
    SQL
  end

  def down
    remove_column :rooms, :include_with_day_pass
  end
end
