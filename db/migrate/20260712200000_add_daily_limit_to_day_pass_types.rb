class AddDailyLimitToDayPassTypes < ActiveRecord::Migration[7.2]
  def change
    # Max DayPass rows of this type per calendar day (per location — the type
    # is already location-scoped). NULL = unlimited, the default for every
    # existing type. See docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md.
    add_column :day_pass_types, :daily_limit, :integer
  end
end
