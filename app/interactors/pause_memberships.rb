class PauseMemberships
  include Interactor

  def call
    subscriptions = Subscription.pause_scheduled

    subscriptions.map do |subscription|
      current_period_end = subscription.current_period_end

      if current_period_end.today? || current_period_end.tomorrow?
        PauseMembership.call(subscription: subscription)
      end
    end
  end

end