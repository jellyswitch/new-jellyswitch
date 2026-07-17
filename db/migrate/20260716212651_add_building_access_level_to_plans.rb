class AddBuildingAccessLevelToPlans < ActiveRecord::Migration[7.2]
  # Replaces the binary always_allow_building_access checkbox on plans with a
  # three-way access level: none / business_hours / all_hours (24-7). Rationale:
  # a coworking membership should be able to grant access *during business
  # hours* without granting 24-7 — the old boolean only offered "24-7 or
  # nothing", which locked members out of the very building they pay for.
  #
  # Backfill preserves every existing config EXACTLY (no silent access change):
  #   always_allow_building_access = true  -> all_hours (2)
  #   always_allow_building_access = false -> none      (0)
  # New plans default to business_hours (1) so a freshly-created plan can never
  # accidentally lock its members out. The old boolean column is left in place
  # (now unused for access decisions) and can be dropped in a later migration.
  def up
    add_column :plans, :building_access_level, :integer, null: false, default: 1
    execute <<~SQL
      UPDATE plans
      SET building_access_level = CASE WHEN always_allow_building_access THEN 2 ELSE 0 END
    SQL
  end

  def down
    remove_column :plans, :building_access_level
  end
end
