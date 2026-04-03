class AddComplimentaryToDayPasses < ActiveRecord::Migration[7.1]
  def change
    add_column :day_passes, :complimentary, :boolean, default: false, null: false
  end
end
