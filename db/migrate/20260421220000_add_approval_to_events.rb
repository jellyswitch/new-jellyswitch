class AddApprovalToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :approved_at, :datetime
    add_column :events, :rejected_at, :datetime
    add_column :events, :submitted_via_app, :boolean, default: false, null: false
    add_index :events, :approved_at

    # All existing events are approved — they came from the web admin flow.
    reversible do |dir|
      dir.up do
        Event.where(approved_at: nil).update_all("approved_at = created_at")
      end
    end
  end
end
