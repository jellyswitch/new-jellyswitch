# == Schema Information
#
# Table name: subscriptions
#
#  id                     :bigint(8)        not null, primary key
#  active                 :boolean          default(TRUE), not null
#  pending                :boolean          default(FALSE), not null
#  subscribable_type      :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  plan_id                :integer          not null
#  stripe_subscription_id :string
#  subscribable_id        :bigint(8)
#
# Indexes
#
#  index_subscriptions_on_subscribable_type_and_subscribable_id  (subscribable_type,subscribable_id)
#

class Subscription < ApplicationRecord
  # Relationships
  belongs_to :plan
  belongs_to :subscribable, polymorphic: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :pending, -> { where(pending: true) }
  scope :for_operator, ->(operator) { joins(:plan).where("plans.operator_id = '?'", operator.id) }

  accepts_nested_attributes_for :plan

  # Instance methods
  def cancel_stripe!
    stripe_subscription.delete
  end

  def stripe_subscription
    Stripe::Subscription.retrieve(self.stripe_subscription_id, {
      api_key: plan.operator.stripe_secret_key,
      stripe_account: plan.operator.stripe_user_id
    })
  end

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
