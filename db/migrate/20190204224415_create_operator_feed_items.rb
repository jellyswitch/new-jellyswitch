class CreateOperatorFeedItems < ActiveRecord::Migration[5.2]
  def change
    create_table :feed_items do |t|
      t.integer :operator_id
      t.integer :user_id
      t.text :original_text

      t.timestamps
    end
  end
end
