class CheckoutJob < ApplicationJob
  queue_as :default

  def perform
    Operator.production.all.each do |operator|
      operator.locations.each do |location|
        location.checkins.open.each do |checkin|
          Time.use_zone(location.time_zone) do
            timestamp =  Time.parse(location.working_day_end)
            corrected_timestamp = timestamp - (checkin.datetime_in.day - timestamp.day).days

            result = Checkins::Checkout.call(checkin: checkin, datetime_out: corrected_timestamp)

            if !result.success?
              puts result.message
              Rollbar.error("Error auto-checking out: #{result.message}")
            end
          end
        end
      end
    end
  end
end
