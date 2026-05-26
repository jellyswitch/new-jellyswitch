class AddMethodToDoorPunches < ActiveRecord::Migration[7.1]
  def change
    add_column :door_punches, :method, :string, null: false, default: "manual"
    add_index  :door_punches, :method
  end
end
