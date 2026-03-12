class AddMeetingRoomLimitsToDayPassTypes < ActiveRecord::Migration[7.1]
  def change
    add_column :day_pass_types, :included_meeting_room_minutes, :integer, default: nil
    add_column :day_pass_types, :overage_rate_in_cents, :integer, default: 0, null: false
  end
end
