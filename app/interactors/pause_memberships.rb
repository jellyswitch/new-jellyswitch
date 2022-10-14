class PauseMemberships
  include Interactor

  def call
    subscriptions = Subscription.pause_scheduled

    subscriptions.map do |subscription|
      current_period_end = subscription.current_period_end

      if PauseDecider.new(current_period_end: current_period_end).should_pause?
        PauseMembership.call(subscription: subscription)
      end
    end
  end
end