class SaveSubscription
  include Interactor

  delegate :subscription, :user, :start_day, to: :context

  def call
    unless user.has_billing? || user.out_of_band?
      context.fail!(message: "Can't add a subscription for someone with no billing info on file.")
    end

    if subscription.save
      Jellyswitch::Events.publish(
        'billing.subscription.create',
        subscription_id: subscription.id,
        start_date: start_day
      )

      Jellyswitch::Events.publish(
        'app.notifiable.create',
        notifiable_id: subscription.id,
        notifiable_type: 'Subscription'
      )
    else
      context.fail!(message: "There was a problem charging for this subscription.")
    end
  end
end
