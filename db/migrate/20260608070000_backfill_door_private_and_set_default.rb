class BackfillDoorPrivateAndSetDefault < ActiveRecord::Migration[7.2]
  # `doors.private` was nullable with no default, so any door created without an
  # explicit flag got NULL. Members' door queries used `where(private: false)`,
  # which drops NULL rows in SQL — silently hiding never-flagged (public) doors
  # from the mobile Keys tab and dashboard. NULL means "not private", so backfill
  # to false and lock in a default + NOT NULL so it can't recur for any operator.
  def up
    execute("UPDATE doors SET private = false WHERE private IS NULL")
    change_column_default :doors, :private, false
    change_column_null :doors, :private, false
  end

  def down
    change_column_null :doors, :private, true
    change_column_default :doors, :private, nil
  end
end
