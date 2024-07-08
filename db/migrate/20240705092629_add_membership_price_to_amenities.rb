class AddMembershipPriceToAmenities < ActiveRecord::Migration[7.0]
  def up
    change_column_default :amenities, :price, from: nil, to: 0.0

    add_column :amenities, :membership_price, :float, default: 0.0

    # Update existing records to have 0 for price if it's currently NULL
    execute <<-SQL
      UPDATE amenities
      SET price = 0.0
      WHERE price IS NULL
    SQL
  end

  def down
    change_column_default :amenities, :price, from: 0.0, to: nil
    remove_column :amenities, :membership_price
  end
end
