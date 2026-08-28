class AddOfficeInventoryFields < ActiveRecord::Migration[7.2]
  # Office Inventory (2026-08-27 plan §7-8): an advertised asking rate for
  # vacant offices (the lease keeps owning the real negotiated price; blank
  # renders "Contact for pricing"), and the staff-flipped coming-available
  # toggle — never derived from lease dates, a tenant might not be leaving.
  def change
    add_column :offices, :asking_rate_in_cents, :integer
    add_column :offices, :coming_available, :boolean, default: false, null: false
    add_column :operators, :office_inventory_enabled, :boolean, default: false, null: false
  end
end
