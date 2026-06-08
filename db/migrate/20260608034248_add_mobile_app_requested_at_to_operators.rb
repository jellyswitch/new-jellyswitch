class AddMobileAppRequestedAtToOperators < ActiveRecord::Migration[7.2]
  def change
    add_column :operators, :mobile_app_requested_at, :datetime
  end
end
