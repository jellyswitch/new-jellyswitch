require 'rails_helper'

RSpec.describe CreateOfficeLease do
  let(:office_lease) { create(:office_lease) }
  subject(:context) { described_class.call(office_lease: office_lease, operator: office_lease.operator) }

  describe '#call' do
    before do
      mock_event(
        'billing.lease.create',
        office_lease_id: office_lease.id,
        operator_id: office_lease.operator.id
      )
    end

    it 'subscribes the organization to the lease plan' do
      office_lease = context.office_lease
      organization = office_lease.organization
      subscription = organization.subscription

      expect(office_lease.end_date).to eq(office_lease.start_date + 1.year)
      expect(subscription.plan).to eq office_lease.plan
      expect(subscription.subscribable).to eq organization
    end
  end
end
