class AddShowcaseButtonColorToOperators < ActiveRecord::Migration[7.2]
  # Showcase product buttons can carry their own color, separate from the
  # shared embed accent (David, 2026-09-02). Blank = inherit the accent.
  def change
    add_column :operators, :showcase_button_color, :string
  end
end
