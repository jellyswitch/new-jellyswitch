require 'rails_helper'

RSpec.describe Billing::LeaseSync do
  let(:office_lease) { create(:office_lease) }
  let(:subscription) { office_lease.subscription }
  let(:organization) { office_lease.organization }
  let(:operator) { office_lease.operator }
  let(:plan) { office_lease.plan }

  describe '.call' do
    context 'creating a future lease' do
      before do
        described_class.call(
          office_lease_id: office_lease.id,
          operator_id: office_lease.operator_id
        )
      end

      it 'creates a subscription in Stripe' do
        expect(subscription.reload.stripe_subscription_id).to_not be_nil
      end
    end

    context 'when creating a historical lease' do
      it 'creates a subscription starting next month' do
        office_lease.initial_invoice_date = 1.month.from_now

        stripe_start_date = (Time.zone.at(office_lease.initial_invoice_date.to_time.to_i) + 2.hours).to_i

        expect_any_instance_of(Operator).to receive(:create_stripe_subscription).once.with(
          organization, subscription, stripe_start_date
        ).and_call_original

        described_class.call(
          office_lease_id: office_lease.id,
          operator_id: office_lease.operator_id
        )

        expect(subscription.reload.stripe_subscription_id).to_not be_nil
      end
    end
  end
end
