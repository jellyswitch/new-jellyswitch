require 'rails_helper'

RSpec.describe Billing::Subscription::SaveSubscription do
  let(:subscription) { double(Subscription, id: 1) }
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
      let(:user) { instance_double(User, has_billing?: false, out_of_band?: false) }

      it 'fails with a message' do
        expect(context.failure?).to be true
        expect(context.message).to eq "Can't add a subscription for someone with no billing info on file."
      end
    end

    context 'when user has billing info' do
      let(:user) { instance_double(User, has_billing?: true) }

      before do
        allow(subscription).to receive(:save) { true }
      end

      it 'is successful' do
        expect(context.success?).to be true
      end
    end

    context 'when user is paying out of band' do
      let(:user) { instance_double(User, has_billing?: false, out_of_band?: true) }

      before do
        allow(subscription).to receive(:save) { true }
      end

      it 'is successful' do
        expect(context.success?).to be true
      end
    end

    context 'when saving subscription is unsuccessful' do
      let(:user) { instance_double(User, has_billing?: true) }

      before do
        allow(subscription).to receive(:save) { false }
      end

      it 'results in failure' do
        expect(context.success?).to be false
        expect(context.message).to eq "There was a problem creating this subscription."
      end
    end
  end
end
