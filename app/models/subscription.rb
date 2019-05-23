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
  # Callbacks
  before_destroy :check_for_stripe_subscription

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

  def has_stripe_subscription?
    stripe_subscription_id.present?
  end

  def stripe_subscription
    if pending?
      nil
    else
      Stripe::Subscription.retrieve(self.stripe_subscription_id, {
        api_key: plan.operator.stripe_secret_key,
        stripe_account: plan.operator.stripe_user_id
      })
    end
  end

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end

  def check_for_stripe_subscription
    if stripe_subscription_id.present?
      raise "Cancel Stripe Subscription first: #{stripe_subscription_id}"
    end
  end

  def pretty_name
    if plan.present?
      plan.pretty_name
    else
      "error"
    end
  end

  def has_days_left?
    if plan.has_day_limit?
      days_left > 0
    else
      true
    end
  end

  def days_left
    report = Jellyswitch::UsageReport.new(subscribable)
    plan.day_limit - report.days_used_count
  end
end
