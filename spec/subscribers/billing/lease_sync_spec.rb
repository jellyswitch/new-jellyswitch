require 'rails_helper'

RSpec.describe Billing::LeaseSync do
  let(:office_lease) { create(:office_lease) }
  let!(:subscription) do
    create(
      :subscription,
      subscribable: office_lease.organization,
      plan: office_lease.plan
    )
  end

  describe '.call' do
    before do
      organization = office_lease.organization
      operator = office_lease.operator
      plan = office_lease.plan

      organization.stripe_customer_id = 'cus_12345'
      plan.stripe_plan_id = 'plan_12345'

      organization.save!
      plan.save!
    end

    it 'creates a subscription in Stripe' do
      result = described_class.call(office_lease_id: office_lease.id, operator_id: office_lease.operator_id)

      expect(result.class).to eq Stripe::Subscription
      expect(result.customer).to eq office_lease.organization.stripe_customer_id
    end
  end
end
