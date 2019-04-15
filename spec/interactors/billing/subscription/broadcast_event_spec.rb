require 'rails_helper'

RSpec.describe Billing::Subscription::BroadcastEvent do
  let(:save_subscription_context) do
    user = create(:user)
    Billing::Subscription::SaveSubscription.call(
      subscription: build(:subscription, subscribable: user),
      user: user,
      start_day: 1.week.from_now.beginning_of_week
    )
  end

  let(:subscription) { save_subscription_context.subscription }
  let(:start_day) { save_subscription_context.start_day }

  subject(:broadcast_event) do
    Billing::Subscription::BroadcastEvent.call(
      subscription: subscription,
      start_day: start_day
    )
  end

  describe '.call' do
    it 'broadcasts events to create subscription and notifications' do
      expect_event(
        'billing.subscription.create',
        subscription_id: subscription.id,
        start_date: start_day
      )

      expect_event(
        'app.notifiable.create',
        notifiable_id: subscription.id,
        notifiable_type: subscription.class.to_s
      )

      broadcast_event
    end
  end
end
