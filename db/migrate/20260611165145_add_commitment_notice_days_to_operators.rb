class AddCommitmentNoticeDaysToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :commitment_notice_days, :integer, default: 30, null: false
  end
end
