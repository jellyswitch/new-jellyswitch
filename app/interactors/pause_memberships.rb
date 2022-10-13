class PauseMemberships
  include Interactor

  def call
    # Subscription.pause_scheduled.map |subscription| do
    # if subscription.current_period_end.today? || subscription.current_period_end.tomorrow?
    #   PauseMembership.call(subscription: subscription)
    # end  
  end

end