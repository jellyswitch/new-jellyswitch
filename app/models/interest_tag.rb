# == Schema Information
#
# Table name: interest_tags
#
#  id          :bigint(8)        not null, primary key
#  product     :string           not null
#  source      :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint(8)        not null
#  operator_id :bigint(8)        not null
#  added_by_id :bigint(8)
#
# A stored Interest tag on a Person (ADR 0022). Which product they want, and
# where the signal came from. Behavioral sources are auto-set/refreshed;
# `staff` is a manual annotation and is sticky (never overwritten by a refresh).
class InterestTag < ApplicationRecord
  belongs_to :user
  belongs_to :operator
  belongs_to :added_by, class_name: "User", optional: true

  acts_as_tenant :operator

  PRODUCTS = %w[office day_pass membership meeting_room].freeze
  # Behavioral sources are inferred from what the Person did (weakest → strongest
  # intent); `staff` is a manual annotation surfaced from an offline conversation.
  #   looked_at  — browsed the product (offices page, plan category) without checking out
  #   concierge  — asked about it in the concierge chat
  #   tour       — toured / expressed interest in person
  #   checkout   — started a checkout for it (strong intent, didn't complete)
  #   last_purchase — bought it (their most recent product)
  SOURCES = %w[looked_at concierge tour checkout last_purchase staff].freeze
  BEHAVIORAL_SOURCES = (SOURCES - %w[staff]).freeze

  validates :product, presence: true, inclusion: { in: PRODUCTS }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :product, uniqueness: { scope: :user_id }

  scope :for_product, ->(product) { where(product: product) }
  scope :staff_set, -> { where(source: "staff") }
  scope :behavioral, -> { where(source: BEHAVIORAL_SOURCES) }

  def staff_set?
    source == "staff"
  end
end
