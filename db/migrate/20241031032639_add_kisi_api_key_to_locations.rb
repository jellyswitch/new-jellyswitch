class AddKisiApiKeyToLocations < ActiveRecord::Migration[7.0]
  def change
    add_column :locations, :kisi_api_key, :string
  end
end
