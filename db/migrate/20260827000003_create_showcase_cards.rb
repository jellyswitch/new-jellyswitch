class CreateShowcaseCards < ActiveRecord::Migration[7.2]
  # Operator-configured link-out cards (e.g. a virtual-office service where
  # sign-up happens externally). Per location, rendered in a Showcase slot:
  # among memberships, among day passes, or standalone (a dedicated page).
  def change
    create_table :showcase_cards do |t|
      t.references :operator, null: false
      t.references :location, null: false
      t.string :label, null: false
      t.text :description
      t.string :price_text
      t.string :url, null: false
      t.string :slot, null: false, default: "standalone"
      t.integer :display_order, default: 0, null: false
      t.boolean :visible, default: true, null: false
      t.timestamps
    end
  end
end
