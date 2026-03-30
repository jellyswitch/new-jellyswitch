class Rooms::DurationButtons < ApplicationComponent
  include ApplicationHelper

  def initialize(room:, datetime_in:, day:, hour:, user:)
    @room = room
    @datetime_in = datetime_in
    @day = day
    @hour = hour
    @user = user
  end

  def max_duration
    @max_duration ||= begin
      min_duration = room.allow_shorter_reservation_duration? ? 15 : 240
      max = room.calculate_max_continuous_duration(start_time: datetime_in)
      [max, min_duration].max
    end
  end

  def min_duration
    room.allow_shorter_reservation_duration? ? 15 : 240
  end

  def default_duration
    [30, max_duration].min
  end

  def confirm_path_template
    confirm_reservations_path(room_id: room.id, day: day, hour: pretty_time(hour), duration: "DURATION_PLACEHOLDER", user_id: user.id)
  end

  private

  attr_reader :room, :datetime_in, :day, :hour, :user
end