class AddOverageRateToLocations < ActiveRecord::Migration[7.2]
  # Phase 1 of the reservation billing redesign (ADR 0012): the
  # "Overage / add-on meeting room time" rate moves UP from
  # day_pass_types.overage_rate_in_cents to the Location, so it applies to any
  # booker of a $0 (call) room — including a group adding a breakout room with
  # no day pass — not only day-pass holders.
  #
  # Additive + reversible. Backfill migrates each location's existing day-pass
  # overage rate up so current day-pass overage billing is preserved: take the
  # MAX overage_rate_in_cents among the day-pass types scoped to that location
  # (or its operator-wide types). Most types default to 0, so most locations
  # backfill to 0 and operators set the real rate in Settings → Payments.
  def up
    add_column :locations, :overage_rate_in_cents, :integer, null: false, default: 0

    execute(<<~SQL)
      UPDATE locations
      SET overage_rate_in_cents = COALESCE((
        SELECT MAX(day_pass_types.overage_rate_in_cents)
        FROM day_pass_types
        WHERE day_pass_types.overage_rate_in_cents > 0
          AND (
            day_pass_types.location_id = locations.id
            OR (day_pass_types.location_id IS NULL
                AND day_pass_types.operator_id = locations.operator_id)
          )
      ), 0)
    SQL
  end

  def down
    remove_column :locations, :overage_rate_in_cents
  end
end
