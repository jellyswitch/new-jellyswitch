class CreateInterestTags < ActiveRecord::Migration[7.1]
  # A Person's Interest is a set of stored tags (ADR 0022) — which product(s)
  # they're drawn to: office / day_pass / membership / meeting_room. A tag is
  # either behavioral (source = looked_at / concierge / tour / checkout /
  # last_purchase) or staff-set (source = staff). Staff-set tags are sticky: a
  # behavioral refresh must not overwrite them. One tag per (user, product).
  def change
    create_table :interest_tags do |t|
      t.references :user, null: false, foreign_key: true
      t.references :operator, null: false, foreign_key: true
      t.string :product, null: false
      t.string :source, null: false
      t.references :added_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # One tag per person per product (a re-detected behavioral signal updates
    # the existing row rather than inserting a duplicate).
    add_index :interest_tags, [:user_id, :product], unique: true
    # The primary read: "everyone interested in <product> at this operator".
    add_index :interest_tags, [:operator_id, :product]
  end
end
