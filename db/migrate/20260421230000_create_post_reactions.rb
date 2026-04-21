class CreatePostReactions < ActiveRecord::Migration[7.1]
  def change
    create_table :post_reactions do |t|
      t.references :post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :emoji, null: false
      t.timestamps
    end
    add_index :post_reactions, [:post_id, :user_id, :emoji], unique: true, name: "index_post_reactions_unique"
  end
end
