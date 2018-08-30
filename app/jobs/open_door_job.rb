class OpenDoorJob < ApplicationJob
  queue_as :default

  def perform(door, user)
    # TODO: Record the attempt and whether it was successful
    # TODO: use traffic control gem here
    puts "-----> DOOR ACCESS #{user.name} opening door: #{door.name} <-----"
    $redis.publish(door.slug, 5)
  end
end
