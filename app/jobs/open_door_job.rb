class OpenDoorJob < ApplicationJob
  queue_as :default

  def perform(door, user)
    # TODO: Publish a redis message to the door's slug, record the attempt and whether it was successful
    puts "-----> DOOR ACCESS #{user.name} opening door: #{door.name} <-----"
  end
end
