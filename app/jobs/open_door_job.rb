class OpenDoorJob < ApplicationJob
  queue_as :default
  # throttle threshold: 1, period: 5.seconds, drop: true

  def perform(door)
    url = "https://api.getkisi.com/locks/#{door.kisi_id}/unlock"
    headers = {
      'Accept' => 'application/json',
      'Content-type' => 'application/json',
      'Authorization' => "KISI-LOGIN #{door.operator.kisi_api_key}"
    }
    HTTParty.post(url, headers: headers)
  rescue StandardError => e
    Rollbar.error(e.message)
  end
end
