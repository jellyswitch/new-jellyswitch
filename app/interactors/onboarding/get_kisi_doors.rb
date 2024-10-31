class Onboarding::GetKisiDoors
  include Interactor

  delegate :location, to: :context

  def call
    if ENV['KISI_TEST_MODE'] == 'stub'
      context.doors = OpenStruct.new(success?: true, doors: [])
      return
    end

    url = "https://api.getkisi.com/locks/"
    headers = {
      "Accept" => "application/json",
      "Content-type" => "application/json",
      "Authorization" => "KISI-LOGIN #{location.kisi_api_key}",
    }
    context.doors = HTTParty.get(url, headers: headers)
    raise "Error getting doors" unless context.doors.success?
  rescue StandardError => e
    context.fail!(message: e.message)
  end
end
