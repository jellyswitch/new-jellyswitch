require 'rails_helper'

RSpec.shared_examples 'billable' do |billable_type|
  let(:billable) do
    case billable_type
    when 'User'
      create(:user, stripe_customer_id: nil)
    when 'Organization'
      create(:organization, stripe_customer_id: nil)
    end
  end

  describe '.call' do
    context 'when Stripe customer does not already exist' do
      before do
        described_class.call(billable_id: billable.id, billable_type: billable.class.name)
      end

      it 'creates a Stripe customer and stores the ID on the billable record' do
        expect(billable.reload.stripe_customer_id).to_not be_nil
      end
    end

    context 'when Stripe customer already exists' do
      before do
        billable.stripe_customer_id = 'cus_12345'
        billable.save!
      end

      it 'does nothing' do
        expect_any_instance_of(Operator).to_not receive(:create_stripe_customer)
        described_class.call(billable_id: billable.id, billable_type: billable.class.name)
      end
    end

    context 'when billable is an Organization' do
      before do
        described_class.call(billable_id: billable.id, billable_type: billable.class.name)
      end
      
      it 'marks the organization as paying out of band' do
        case billable_type
        when 'Organization'
          expect(billable.reload.out_of_band?).to be true
        end
      end
    end
  end
end

RSpec.describe Billing::CustomerSync do
  include_examples 'billable', 'User'
  include_examples 'billable', 'Organization'
end
