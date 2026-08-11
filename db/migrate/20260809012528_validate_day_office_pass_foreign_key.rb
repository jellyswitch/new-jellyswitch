class ValidateDayOfficePassForeignKey < ActiveRecord::Migration[7.2]
  # validate_foreign_key has no registered CommandRecorder inverse (Postgres
  # VALIDATE CONSTRAINT can't be undone short of dropping and re-adding the FK
  # as NOT VALID), so this needs up/down rather than change — same pattern as
  # 20260807210000_normalize_bundle_meeting_minutes_to_per_day.rb.
  def up
    validate_foreign_key :reservations, column: :day_office_pass_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
