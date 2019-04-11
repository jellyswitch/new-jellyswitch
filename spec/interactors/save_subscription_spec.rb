require 'rails_helper'

RSpec.describe SaveSubscription do
  let(:subscription) { create(:subscription, :for_user) }
  let(:user) { subscription.subscribable }
  let(:start_day) { 1.week.from_now.beginning_of_week }

  subject(:context) do
    described_class.call(
      subscription: subscription,
      user: user,
      start_day: start_day
    )
  end

  describe '#call' do
    context 'when user has no billing info' do
      before do
        user.stripe_customer_id = nil
        user.out_of_band = false
      end

      it 'fails with a message' do
        expect(context.failure?).to be true
        expect(context.message).to eq "Can't add a subscription for someone with no billing info on file."
      end
    end

    context 'when user has billing info' do
      before do
        user.stripe_customer_id = "cus_12345"
        user.card_added = true
        mock_event(
          'billing.subscription.create',
          subscription_id: subscription.id,
          start_date: start_day
        )

        mock_event(
          'app.notifiable.create',
          notifiable_id: subscription.id,
          notifiable_type: 'Subscription'
        )
      end

      it 'creates a subscription' do
        expect(context.success?).to be true
        expect(subscription.id).to_not be nil
      end
    end

    context 'when user is paying out of band' do
      before do
        user.stripe_customer_id = nil
        user.out_of_band = true

        mock_event(
          'billing.subscription.create',
          subscription_id: subscription.id,
          start_date: start_day
        )

        mock_event(
          'app.notifiable.create',
          notifiable_id: subscription.id,
          notifiable_type: 'Subscription'
        )
      end

      it 'creates a subscription' do
        expect(context.success?).to be true
        expect(subscription.id).to_not be nil
      end
    end
  end
end
