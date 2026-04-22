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

class Subscription < ApplicationRecord
  # Callbacks
  before_destroy :check_for_stripe_subscription

  # Relationships
  belongs_to :plan
  belongs_to :billable, polymorphic: true
  belongs_to :subscribable, polymorphic: true
  has_many :office_leases
  has_many :discount_redemptions, as: :discountable, dependent: :nullify

  # Scopes
  scope :active, -> { where(active: true) }
  scope :pending, -> { where(pending: true) }
  scope :for_operator, ->(operator) { joins(:plan).where("plans.operator_id = '?'", operator.id) }
  scope :for_location, ->(location) do
          joins(:plan).where(plans: { id: Plan.for_location(location).map(&:id) })
        end
  scope :for_week, ->(week_start, week_end) { where("created_at > ? and created_at <= ?", week_start, week_end) }

  accepts_nested_attributes_for :plan

  delegate :operator, :location, to: :subscribable

  # Instance methods
  def cancel_stripe!(prorate: true)
    sub = stripe_subscription
    return unless sub
    sub.delete(prorate: prorate)
  end

  def set_stripe_to_cancel!
    sub = stripe_subscription
    return unless sub
    sub.save(cancel_at_period_end: true)
  end

  def has_stripe_subscription?
    stripe_subscription_id.present? && stripe_subscription.id.present?
  rescue StandardError => e
    false
  end

  def stripe_subscription
    if pending? || stripe_subscription_id.blank?
      nil
    else
      Stripe::Subscription.retrieve(self.stripe_subscription_id, {
        api_key: plan.location.stripe_secret_key,
        stripe_account: plan.location.stripe_user_id,
      })
    end
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e)
    nil
  end

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end

  def check_for_stripe_subscription
    if stripe_subscription_id.present? && active?
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
    return true # ignore day limits for now
    !plan.has_day_limit? || days_left > 0
  end

  def days_left
    report = Jellyswitch::UsageReport.new(subscribable)
    plan.day_limit - report.days_used_count
  end

  def current_billing_period
    return [start_date.beginning_of_day, Time.current] unless has_stripe_subscription?

    sub = stripe_subscription
    [Time.at(sub.current_period_start), Time.at(sub.current_period_end)]
  rescue StandardError => e
    [start_date.beginning_of_day, Time.current]
  end

  def has_end_date?
    sub = stripe_subscription
    sub.present? && sub.cancel_at.present?
  rescue StandardError => e
    false
  end

  def end_date
    sub = stripe_subscription
    return nil unless sub&.cancel_at
    Time.at(sub.cancel_at)
  end

  def set_end_date!(date)
    s = stripe_subscription
    return unless s
    s.cancel_at = date.to_i
    s.save
  end

  def has_canceled_at?
    sub = stripe_subscription
    sub.present? && sub.canceled_at.present?
  end

  def has_period_end?
    sub = stripe_subscription
    sub.present? && sub.current_period_end.present?
  end

  def current_period_end
    sub = stripe_subscription
    return nil unless sub&.current_period_end
    Time.at(sub.current_period_end)
  end

  def canceled_at
    sub = stripe_subscription
    return nil unless sub&.canceled_at
    Time.at(sub.canceled_at)
  end

  def ended_at
    sub = stripe_subscription
    return nil unless sub&.ended_at
    Time.at(sub.ended_at)
  end
end
