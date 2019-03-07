class OpenDoorJob < ApplicationJob
  queue_as :default
  throttle threshold: 1, period: 5.seconds, drop: true

  def perform(door)
    url = "https://api.getkisi.com/locks/#{door.kisi_id}/unlock"
    headers = {
      'Accept' => 'application/json',
      'Content-type' => 'application/json',
      'Authorization' => "KISI-LOGIN #{door.operator.kisi_api_key}"
    }
    puts url.inspect
    puts headers.inspect

    puts HTTParty.post(url, headers: headers)
  end
end
