class FixOutofbandAndCardaddedUsers < ActiveRecord::Migration[7.0]
  def change
    User.where(out_of_band: true, card_added: true).update_all(out_of_band: false)

    # User.where(out_of_band: true, card_added: true).map { |user|
    #   if user.subscriptions.active.first.stripe_subscription.billing == "send_invoice"`
    #     Billing::Subscription::CancelStripeSubscription.call(subscription: user.subscriptions.active.first)
    #   end
    # end
    # }
  end
end
