class Plan < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  # Relationships
  has_many :subscriptions

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Enumeration options
  INTERVAL_OPTIONS = [
    "once",
    "hourly",
    "daily",
    "monthly",
    "annually"
  ]

  # Scopes
  scope :available, ->() { where(available: true) }
  scope :visible, ->() { where(visible: true) }
  
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
    pretty_amount = number_to_currency(amount_in_cents / 100.0)
    "#{name} (#{pretty_amount} / #{interval})"
  end
end
