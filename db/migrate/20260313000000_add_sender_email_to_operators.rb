class AddSenderEmailToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :sender_email, :string
  end
end
