# typed: false
module SubscriptionsHelper
  def find_subscription(key=:id)
    @subscription = Subscription.find(params[key])
  end

  def compute_start_day
    if params[:subscription][:start_day].present?
      Time.zone.at(params[:subscription][:start_day].to_i) + 2.hours
    else
      nil
    end
  end
end