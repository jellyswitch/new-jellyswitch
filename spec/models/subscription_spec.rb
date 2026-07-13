# == Schema Information
#
# Table name: subscriptions
#
#  id                                  :bigint(8)        not null, primary key
#  active                              :boolean          default(TRUE), not null
#  billable_type                       :string
#  cancelling_at_end_of_billing_period :boolean          default(FALSE), not null
#  paused                              :boolean          default(FALSE), not null
#  pending                             :boolean          default(FALSE), not null
#  start_date                          :date             not null
#  subscribable_type                   :string
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  billable_id                         :bigint(8)
#  plan_id                             :integer          not null
#  stripe_subscription_id              :string
#  subscribable_id                     :bigint(8)
#
# Indexes
#
#  index_subscriptions_on_billable_type_and_billable_id          (billable_type,billable_id)
#  index_subscriptions_on_subscribable_type_and_subscribable_id  (subscribable_type,subscribable_id)
#
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
      before do
        allow(subscription).to receive(:stripe_subscription).and_return(stripe_subscription_mock)
      end

      it 'deletes the stripe subscription with prorate false by default (no refund per ops policy)' do
        expect(stripe_subscription_mock).to receive(:delete).with(prorate: false)
        subscription.cancel_stripe!
      end

      it 'forwards prorate: true when explicitly requested' do
        expect(stripe_subscription_mock).to receive(:delete).with(prorate: true)
        subscription.cancel_stripe!(prorate: true)
      end
    end

    describe '#set_stripe_to_cancel!' do
      before do
        allow(subscription).to receive(:stripe_subscription).and_return(stripe_subscription_mock)
      end

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

    describe "activity logging" do
      let(:user) { create(:user) }

      it "logs :subscription_started on create when subscribable is a User" do
        user # force creation outside expect (signup Activity belongs to this user)
        expect {
          create(:subscription, subscribable: user, billable: user)
        }.to change(Activity.where(kind: "subscription_started"), :count).by(1)

        activity = Activity.where(kind: "subscription_started").last
        expect(activity.user).to eq(user)
        expect(activity.subject).to eq(Subscription.last)
      end

      it "denormalizes plan name and start_date into payload" do
        subscription = create(:subscription, subscribable: user, billable: user)
        payload = Activity.last.payload

        expect(payload["plan_name"]).to eq(subscription.plan.pretty_name)
        expect(payload["start_date"]).to eq(subscription.start_date.iso8601)
      end

      it "logs :subscription_ended when active flips from true to false" do
        subscription = create(:subscription, subscribable: user, billable: user, active: true)

        expect { subscription.update!(active: false) }.to change(Activity, :count).by(1)
        expect(Activity.last.kind).to eq("subscription_ended")
      end

      it "does not log :subscription_ended on unrelated updates" do
        subscription = create(:subscription, subscribable: user, billable: user, active: true)

        expect { subscription.update!(paused: true) }.not_to change(Activity.where(kind: "subscription_ended"), :count)
      end

      it "does not log :subscription_ended twice if active is reset" do
        subscription = create(:subscription, subscribable: user, billable: user, active: true)
        subscription.update!(active: false)

        expect { subscription.update!(active: false) }.not_to change(Activity, :count)
      end

      it "does not log subscription_started/ended when subscribable is not a User (e.g. Organization)" do
        expect {
          create(:subscription, :for_organization)
        }.not_to change(Activity.where(kind: ["subscription_started", "subscription_ended"]), :count)
      end
    end
  end

  describe "#clear_churn_suppression (returning member falsifies the churn prediction)" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:plan) { create(:plan, operator: operator, location: location, plan_type: "individual") }
    let(:member) { create(:user, operator: operator, original_location: location) }

    it "clears a machine-set churn suppression when they subscribe again" do
      member.update!(marketing_suppressed: true, marketing_suppressed_reason: "Churned: Moving away")

      create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      member.reload
      expect(member.marketing_suppressed).to be false
      expect(member.marketing_suppressed_reason).to be_nil
    end

    it "never clears an admin-set suppression" do
      member.update!(marketing_suppressed: true, marketing_suppressed_reason: "Suppressed by admin")

      create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)

      member.reload
      expect(member.marketing_suppressed).to be true
      expect(member.marketing_suppressed_reason).to eq("Suppressed by admin")
    end

    it "no-ops for unsuppressed members and org subscriptions" do
      expect {
        create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)
      }.not_to change { member.reload.marketing_suppressed }

      org_owner = create(:user, operator: operator, original_location: location)
      org = create(:organization, operator: operator, owner: org_owner)
      org_owner.update!(marketing_suppressed: true, marketing_suppressed_reason: "Churned: Moving away")

      create(:subscription, plan: plan, subscribable: org, subscribable_type: "Organization",
                            billable: org, billable_type: "Organization", stripe_subscription_id: nil)

      # The org subscribing is not the owner personally returning.
      expect(org_owner.reload.marketing_suppressed).to be true
    end
  end
end
