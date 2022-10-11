
module DoorsHelper
  def url(door)
    "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
  end

  def headers(door)
    {
      'Accept' => 'application/json',
      'Content-type' => 'application/json',
      'Authorization' => "KISI-LOGIN #{door.operator.kisi_api_key}"
    }
  end
end
