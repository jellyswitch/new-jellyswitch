class AddShowcaseFieldsToProducts < ActiveRecord::Migration[7.2]
  # Showcase (ADR 0027 / 2026-08-27 plan): per-product curation — free-text
  # what's-included lines, the featured (highlighted) tier, and display order.
  # `visible` already gates appearance (visible in app = shown on website).
  def change
    add_column :day_pass_types, :features, :text, array: true, default: [], null: false
    add_column :day_pass_types, :featured, :boolean, default: false, null: false
    add_column :day_pass_types, :display_order, :integer, default: 0, null: false

    add_column :plans, :features, :text, array: true, default: [], null: false
    add_column :plans, :featured, :boolean, default: false, null: false
    add_column :plans, :display_order, :integer, default: 0, null: false

    add_column :operators, :showcase_enabled, :boolean, default: false, null: false
  end
end
