class AddLocationIdToModels < ActiveRecord::Migration[7.0]
  TABLES_WITHOUT_LOCATION_FIELD = [:day_passes, :member_feedbacks, :feed_items, :weekly_updates]
  TABLES_WITHOUT_LOCATION_INDEX = [:posts, :checkins, :announcements]

  def up
    TABLES_WITHOUT_LOCATION_FIELD.each do |table|
      add_column table, :location_id, :integer
      add_index table, :location_id
    end

    TABLES_WITHOUT_LOCATION_INDEX.each do |table|
      add_index table, :location_id
    end
  end

  def down
    TABLES_WITHOUT_LOCATION_FIELD.each do |table|
      remove_column table, :location_id
    end

    TABLES_WITHOUT_LOCATION_INDEX.each do |table|
      remove_index table, :location_id
    end
  end
end
