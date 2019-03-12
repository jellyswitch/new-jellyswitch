# == Schema Information
#
# Table name: subscriptions
#
#  id                     :bigint(8)        not null, primary key
#  plan_id                :integer          not null
#  user_id                :integer          not null
#  active                 :boolean          default(TRUE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  stripe_subscription_id :string
#

class Subscription < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :plan

  # Scopes
  scope :active, ->() { where(active: true) }
  scope :for_operator, ->(operator) { joins(:plan).where("plans.operator_id = '?'", operator.id) }

  # Instance methods
  def cancel_stripe!
    stripe_subscription.delete
  end

  def stripe_subscription
    Stripe::Subscription.retrieve(self.stripe_subscription_id, {stripe_account: plan.operator.stripe_user_id})
  end

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
