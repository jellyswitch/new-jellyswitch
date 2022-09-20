class Rooms::DurationButtons < ApplicationComponent
  include ApplicationHelper

  def initialize(room:, datetime_in:, day:, hour:, user:)
    @room = room
    @datetime_in = datetime_in
    @day = day
    @hour = hour
    @user = user
  end

  def allow_shorter_reservation_duration?
    room.allow_shorter_reservation_duration?
  end

  def find_available_durations
    available_durations = []
    all_durations = [30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 360, 390, 420, 450, 480]

    all_durations.each do |duration|
      if room.available_at?(datetime_in + duration.minutes)
        available_durations << duration
      else
        break
      end
    end

    if allow_shorter_reservation_duration?
      available_durations
    else
      available_durations = available_durations.keep_if { |duration| duration >= 240 }
    end

    available_durations
  end

  private

  attr_reader :room, :datetime_in, :day, :hour, :user
end