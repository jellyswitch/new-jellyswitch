class AddRoleToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :role, :string, null: false, default: "unassigned"

    User.all.map do |user|
      if user.admin == true
        user.update(role: 'admin')
      end
    end

    User.all.map do |user|
      if user.superadmin == true
        user.update(role: 'superadmin')
      end
    end
  end
end
