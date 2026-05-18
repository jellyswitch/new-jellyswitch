class AddHomeZipToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :home_zip, :string
    add_index :users, :home_zip
  end
end
