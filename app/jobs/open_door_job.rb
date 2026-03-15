
class OpenDoorJob < ApplicationJob
  queue_as :default
  throttle threshold: 1, period: 5.seconds, drop: true
  include DoorsHelper

  rescue_from Suo::LockClientError, with: :handle_lock_error

  def perform(door, user)
    response = HTTParty.post(url(door), headers: headers(door))
    DoorPunch.create!(user: user, door: door, json: response)
  rescue StandardError => e
    Honeybadger.notify(e.message)
  end

  private

  def handle_lock_error(exception)
    Rails.logger.warn("OpenDoorJob: Redis lock contention, dropping job: #{exception.message}")
  end
end
