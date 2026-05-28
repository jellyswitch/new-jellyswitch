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

  # NOTE: the confirm URL is now assembled client-side via URLSearchParams
  # in the template's <script> (from data-* attributes), so there's no
  # `confirm_path_template` here anymore. Building it as a string and
  # dropping it into an href let Turbo's outerHTML snapshot cache re-escape
  # `&` → `&amp;`, which broke param parsing on WebView cache-restore.

  private

  attr_reader :room, :datetime_in, :day, :hour, :user
end