require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe 'associations' do
    it { should belong_to(:plan) }
    it { should belong_to(:billable) }
    it { should belong_to(:subscribable) }
    it { should have_many(:office_leases) }
  end

  describe 'delegations' do
    it { should delegate_method(:operator).to(:subscribable) }
    it { should delegate_method(:location).to(:subscribable) }
  end

  describe 'scopes' do
    let!(:active_subscription) { create(:subscription, active: true) }
    let!(:inactive_subscription) { create(:subscription, active: false) }
    let!(:pending_subscription) { create(:subscription, pending: true) }

    describe '.active' do
      it 'returns only active subscriptions' do
        expect(Subscription.active).to include(active_subscription)
        expect(Subscription.active).not_to include(inactive_subscription)
      end
    end

    describe '.pending' do
      it 'returns only pending subscriptions' do
        expect(Subscription.pending).to include(pending_subscription)
        expect(Subscription.pending).not_to include(active_subscription)
      end
    end

    describe '.for_operator' do
      let(:operator) { create(:operator) }
      let(:plan) { create(:plan, operator: operator) }
      let!(:subscription) { create(:subscription, plan: plan) }

      it 'returns subscriptions for the given operator' do
        expect(Subscription.for_operator(operator)).to include(subscription)
      end
    end

    describe '.for_location' do
      let(:location) { create(:location) }
      let(:plan) { create(:plan, location: location) }
      let!(:subscription) { create(:subscription, plan: plan) }

      it 'returns subscriptions for the given location' do
        expect(Subscription.for_location(location)).to include(subscription)
      end
    end

    describe '.for_week' do
      let!(:subscription) { create(:subscription) }

      it 'returns subscriptions created within the date range' do
        week_start = 1.day.ago
        week_end = 1.day.from_now
        expect(Subscription.for_week(week_start, week_end)).to include(subscription)
      end
    end
  end

  describe 'stripe integration' do
    let(:subscription) { create(:subscription) }
    let(:stripe_subscription_mock) { double('Stripe::Subscription') }

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(stripe_subscription_mock)
    end

    describe '#cancel_stripe!' do
      it 'deletes the stripe subscription' do
        expect(stripe_subscription_mock).to receive(:cancel)
        subscription.cancel_stripe!
      end
    end

    describe '#set_stripe_to_cancel!' do
      it 'sets the stripe subscription to cancel at period end' do
        expect(stripe_subscription_mock).to receive(:save).with(cancel_at_period_end: true)
        subscription.set_stripe_to_cancel!
      end
    end

    describe '#has_stripe_subscription?' do
      context 'when stripe subscription exists' do
        before do
          allow(stripe_subscription_mock).to receive(:id).and_return('stripe_id')
          subscription.stripe_subscription_id = 'stripe_id'
        end

        it 'returns true' do
          expect(subscription.has_stripe_subscription?).to be true
        end
      end

      context 'when stripe subscription does not exist' do
        before do
          subscription.stripe_subscription_id = nil
        end

        it 'returns false' do
          expect(subscription.has_stripe_subscription?).to be false
        end
      end
    end
  end

  describe 'instance methods' do
    let(:subscription) { create(:subscription) }

    describe '#pretty_datetime' do
      it 'returns formatted datetime string' do
        expect(subscription.pretty_datetime).to eq(subscription.updated_at.strftime("%m/%d/%Y at %l:%M%P"))
      end
    end

    describe '#pretty_name' do
      context 'when plan exists' do
        it 'returns plan pretty name' do
          expect(subscription.pretty_name).to eq(subscription.plan.pretty_name)
        end
      end

      context 'when plan does not exist' do
        before { subscription.plan = nil }

        it 'returns error' do
          expect(subscription.pretty_name).to eq('error')
        end
      end
    end

    describe '#has_days_left?' do
      it 'returns true' do
        expect(subscription.has_days_left?).to be true
      end
    end
  end

  describe 'callbacks' do
    describe 'before_destroy' do
      let(:subscription) { create(:subscription, active: true, stripe_subscription_id: 'stripe_id') }

      it 'raises error if active stripe subscription exists' do
        expect { subscription.destroy }.to raise_error(RuntimeError, /Cancel Stripe Subscription first/)
      end
    end
  end
end
