# typed: false
class OpenDoorJob < ApplicationJob
  queue_as :default
  throttle threshold: 1, period: 5.seconds, drop: true

  def perform(door, user)
    url = "https://api.getkisi.com/locks/#{door.kisi_id}/unlock"
    headers = {
      'Accept' => 'application/json',
      'Content-type' => 'application/json',
      'Authorization' => "KISI-LOGIN #{door.operator.kisi_api_key}"
    }
    response = HTTParty.post(url, headers: headers)
    json = JSON.parse(response, symbolize_names: true)
    DoorPunch.create!(user: current_user, door: @door, json: json)
  rescue StandardError => e
    Rollbar.error(e.message)
  end
end
