class DedupeWeeklyUpdatesAndAddUniqueIndex < ActiveRecord::Migration[7.2]
  # One-time cleanup of duplicate weekly updates (and their feed cards) created
  # before WeeklyUpdates::Save became idempotent, followed by the unique index
  # that enforces "one weekly update per (location, week_start)" going forward.
  #
  # Runs inside the default DDL transaction so the cleanup and the index land
  # atomically — if the index can't be created, the deletes roll back too.
  def up
    # 1. Duplicate weekly_update ids: every row that shares (location_id,
    #    week_start) with an older row. Keeps the earliest id per group.
    dup_ids = select_values(<<~SQL).map(&:to_i)
      SELECT a.id
      FROM weekly_updates a
      JOIN weekly_updates b
        ON a.location_id = b.location_id
       AND a.week_start  = b.week_start
       AND a.id > b.id
    SQL

    if dup_ids.any?
      id_list = dup_ids.join(",")

      # 2. Remove the feed cards that point at the duplicate updates.
      execute(<<~SQL)
        DELETE FROM feed_items
        WHERE blob->>'type' = 'weekly-update'
          AND (blob->>'weekly_update_id')::bigint IN (#{id_list})
      SQL

      # 3. Remove the duplicate updates themselves.
      execute("DELETE FROM weekly_updates WHERE id IN (#{id_list})")
    end

    # 4. Collapse any duplicate feed cards for the SAME surviving update
    #    (notifiable fired more than once) — keep the earliest card.
    execute(<<~SQL)
      DELETE FROM feed_items a
      USING feed_items b
      WHERE a.blob->>'type' = 'weekly-update'
        AND b.blob->>'type' = 'weekly-update'
        AND a.blob->>'weekly_update_id' = b.blob->>'weekly_update_id'
        AND a.id > b.id
    SQL

    # 5. Enforce uniqueness going forward.
    add_index :weekly_updates, [:location_id, :week_start],
              unique: true, name: "idx_weekly_updates_location_week_unique"
  end

  def down
    remove_index :weekly_updates, name: "idx_weekly_updates_location_week_unique"
  end
end
