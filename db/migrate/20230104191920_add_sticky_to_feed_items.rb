class AddStickyToFeedItems < ActiveRecord::Migration[7.0]
  def change
    add_column :feed_items, :sticky, :boolean, default: :false
  end
end
