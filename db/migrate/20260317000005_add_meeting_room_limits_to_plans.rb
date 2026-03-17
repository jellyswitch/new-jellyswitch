class AddMeetingRoomLimitsToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :included_meeting_room_minutes, :integer
    add_column :plans, :overage_rate_in_cents, :integer, default: 0
  end
end
