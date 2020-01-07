class Rooms::DurationButton < ApplicationComponent
  include ApplicationHelper

  def initialize(room:, day:, hour:, user:, duration: duration)
    @room = room
    @day = day
    @hour = hour
    @user = user
    @duration = duration
  end

  private

  attr_reader :room, :day, :hour, :user, :duration

  def label
    if duration < 60
      delimiter = quantize(duration, "minute")
      "#{duration} #{delimiter}"
    else
      hours = (duration.to_f / 60.0)
      delimiter = quantize(hours, "hour")
      "#{number_to_human(hours)} #{delimiter}"
    end
  end
end