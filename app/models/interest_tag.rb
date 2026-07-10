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
  # Tags backed by an actual purchase (carry a last_purchased_at). The newest is
  # the Person's most-recent buy.
  scope :purchased, -> { where.not(last_purchased_at: nil) }

  def staff_set?
    source == "staff"
  end

  # Concierge chat intents (embed/concierge_controller) map to interest products.
  CONCIERGE_INTENT_TO_PRODUCT = {
    "office" => "office",
    "day_office" => "office",
    "conference_room" => "meeting_room",
    "day_pass" => "day_pass",
    "day_pass_bundle" => "day_pass",
    "membership" => "membership",
  }.freeze

  # Upsert a Person's interest in a product. One row per (user, product): a new
  # signal updates the existing tag rather than duplicating. Staff-set tags are
  # STICKY — a behavioral signal never overwrites a manual annotation, but a
  # staff edit always wins. Scoped to the user's operator regardless of ambient
  # tenant (works from the embed concierge, a backfill, or the admin UI).
  def self.record(user:, product:, source:, added_by: nil, at: nil)
    product = product.to_s
    source = source.to_s
    return nil unless PRODUCTS.include?(product) && SOURCES.include?(source)

    ActsAsTenant.with_tenant(user.operator) do
      retried = false
      begin
        tag = find_or_initialize_by(user_id: user.id, product: product)
        return tag if tag.persisted? && tag.staff_set? && source != "staff"

        tag.operator = user.operator
        tag.source = source
        tag.added_by = (source == "staff" ? added_by : nil)
        # Stamp the purchase time for purchase signals only, and only ever move it
        # FORWARD — so a later concierge/looked_at signal doesn't erase it, and an
        # older replayed purchase (backfill ordering) can't regress a newer one.
        if source == "last_purchase"
          tag.last_purchased_at = [tag.last_purchased_at, (at || Time.current)].compact.max
        end
        tag.save!
        tag
      rescue ActiveRecord::RecordNotUnique
        # A concurrent insert won the race (first tag for this user+product). Retry
        # once — find_or_initialize_by now finds the row and UPDATEs it. This keeps
        # a purchase-time double-submit from ever rolling back the sale.
        raise if retried
        retried = true
        retry
      end
    end
  end

  # Record interest from a concierge chat intent, if it maps to a product.
  def self.record_from_concierge_intent(user, intent)
    product = CONCIERGE_INTENT_TO_PRODUCT[intent.to_s]
    return nil unless product

    record(user: user, product: product, source: "concierge")
  end
end
