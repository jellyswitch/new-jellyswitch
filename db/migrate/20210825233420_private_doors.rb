class PrivateDoors < ActiveRecord::Migration[6.1]
  def change
    add_column :doors, :private, :boolean
    belongs_to :doors, :private_owner, polymorphic: true, null: true
  end
end
