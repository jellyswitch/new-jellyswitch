class AddFirebaseProjectIdToOperators < ActiveRecord::Migration[7.0]
  def change
    add_column :operators, :firebase_project_id, :string
  end
end
