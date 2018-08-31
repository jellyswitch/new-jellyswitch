class OpenDoorJob < ApplicationJob
  queue_as :default
  throttle threshold: 1, period: 5.seconds, drop: true

  def perform(door)
    $redis.publish(door.slug, 5)
  end
end
