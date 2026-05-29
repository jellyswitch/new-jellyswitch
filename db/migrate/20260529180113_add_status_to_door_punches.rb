class AddStatusToDoorPunches < ActiveRecord::Migration[7.1]
  def change
    # "unlocked" default keeps every existing (synchronous) punch truthful —
    # they only ever existed because the door actually opened. The optimistic
    # auto-unlock path explicitly writes "pending", which KisiUnlockJob then
    # transitions to "unlocked" or "failed".
    add_column :door_punches, :status, :string, null: false, default: "unlocked"
    add_index  :door_punches, :status
  end
end
