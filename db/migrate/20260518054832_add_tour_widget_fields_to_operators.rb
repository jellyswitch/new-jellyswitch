class AddTourWidgetFieldsToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :tour_widget_enabled,       :boolean, default: false, null: false
    add_column :operators, :tour_widget_thank_you_url, :string
  end
end
