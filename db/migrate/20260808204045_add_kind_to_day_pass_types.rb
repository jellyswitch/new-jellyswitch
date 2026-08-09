class AddKindToDayPassTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :day_pass_types, :kind, :string, null: false, default: "standard"
  end
end
