# == Schema Information
#
# Table name: plans
#
#  id              :bigint(8)        not null, primary key
#  amount_in_cents :integer          not null
#  available       :boolean          default(TRUE), not null
#  interval        :string           not null
#  name            :string           not null
#  slug            :string
#  visible         :boolean          default(TRUE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  operator_id     :integer          default(1), not null
#  stripe_plan_id  :string
#
# Indexes
#
#  index_plans_on_operator_id  (operator_id)
#

class Plan < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  # Relationships
  has_many :subscriptions
  belongs_to :operator
  acts_as_tenant :operator

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Scopes
  scope :available, ->() { where(available: true) }
  scope :visible, ->() { where(visible: true) }

  # Stripe stuff
  after_create :create_stripe_plan
  def create_stripe_plan
    plan = Stripe::Plan.create({
      amount: amount_in_cents,
      interval: stripe_interval,
      product: { name: plan_name },
      currency: 'usd',
      id: plan_slug
    })
    self.stripe_plan_id = plan.id
    self.save
  end

  def stripe_plan
    Stripe::Plan.retrieve(self.stripe_plan_id)
  end

  def plan_name
    "#{operator.name} #{name}"
  end

  def stripe_interval
    {
      "daily" => "day",
      "weekly" => "week",
      "monthly" => "month",
      "annualy" => "year"
    }[interval]
  end

  def short_interval
    {
      "daily" => "day",
      "weekly" => "wk",
      "monthly" => "mo",
      "annualy" => "yr"
    }[interval]
  end

  def plan_slug
    "#{operator.name.parameterize}-#{slug}"
  end

  # Enumeration options
  INTERVAL_OPTIONS = [
    "hourly",
    "daily",
    "monthly",
    "annually"
  ]
  
  # Class methods
  def self.options_for_interval
    INTERVAL_OPTIONS
  end

  def self.options_for_select
    Plan.available.visible.map do |plan|
      [plan.pretty_name, plan.id]
    end
  end

  # Instance methods
  def pretty_name
    "#{name} (#{pretty_price})"
  end

  def pretty_amount
    number_to_currency(amount_in_cents / 100.0)
  end

  def pretty_price
    "#{pretty_amount} / #{short_interval}"
  end
end
