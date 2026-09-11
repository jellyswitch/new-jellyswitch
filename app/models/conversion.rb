# == Schema Information
#
# Table name: conversions
#
#  id              :bigint(8)        not null, primary key
#  amount_cents    :integer          default(0), not null
#  campaign        :string
#  channel         :string
#  kind            :string           not null
#  landing_page    :string
#  medium          :string
#  occurred_at     :datetime         not null
#  referrer_domain :string
#  self_serve      :boolean          default(TRUE), not null
#  source          :string
#  subject_type    :string
#  surface         :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  actor_id        :bigint(8)
#  ahoy_visit_id   :bigint(8)
#  location_id     :bigint(8)
#  operator_id     :bigint(8)        not null
#  subject_id      :bigint(8)
#  user_id         :bigint(8)
#
# One row per conversion: a signup, a lead (tour request / concierge chat),
# or a purchase. Snapshots the person's first-touch attribution so the
# Conversions report can answer "signups / purchases / revenue by channel"
# without re-deriving it later. Written by Conversion.record from every
# purchase and signup path (web, app, widgets, admin).

class Conversion < ApplicationRecord
  belongs_to :operator
  acts_as_tenant :operator

  belongs_to :location, optional: true
  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :ahoy_visit, class_name: "Ahoy::Visit", optional: true

  LEAD_KINDS    = %w[signup tour_request chat_lead].freeze
  REVENUE_KINDS = %w[membership day_pass day_pass_bundle room_reservation office_lease].freeze
  KINDS         = (LEAD_KINDS + REVENUE_KINDS).freeze
  SURFACES      = %w[web app widget admin backfill].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :surface, inclusion: { in: SURFACES }, allow_nil: true
  validates :occurred_at, presence: true

  scope :revenue, -> { where(kind: REVENUE_KINDS) }
  scope :leads, -> { where(kind: LEAD_KINDS) }
  scope :between, ->(range) { where(occurred_at: range) }
  scope :for_location, ->(location) { where(location_id: location.id) }

  # Safe entry point: never raises into a purchase path. Assigns the person's
  # first-touch attribution on the way if they don't have one yet (using the
  # current visit as a fallback for brand-new signups).
  #
  #   Conversion.record(kind: "day_pass", user: user, subject: day_pass,
  #                     amount_cents: 3500, surface: "web", actor: current_user,
  #                     visit: current_visit, operator: current_tenant, location: current_location)
  def self.record(kind:, operator:, user: nil, subject: nil, amount_cents: nil, surface: "web",
                  actor: nil, visit: nil, location: nil, occurred_at: Time.current)
    return nil if operator.nil?

    if user
      Attribution::AssignFirstTouch.call(user, fallback_visit: visit, surface: surface)
    end

    attrs = {
      operator: operator,
      location: location || user&.original_location,
      user: user,
      subject: subject,
      kind: kind.to_s,
      amount_cents: amount_cents.to_i,
      surface: surface,
      actor: actor,
      self_serve: actor.nil? || user.nil? || actor.id == user.id,
      ahoy_visit_id: visit&.id,
      occurred_at: occurred_at,
      channel: user&.acquisition_channel || Attribution::Classifier.call(surface: surface).channel,
      source: user&.acquisition_source,
      medium: user&.acquisition_medium,
      campaign: user&.acquisition_campaign,
      referrer_domain: user&.acquisition_referrer,
      landing_page: user&.acquisition_landing_page,
    }

    if subject
      existing = ActsAsTenant.without_tenant { Conversion.find_by(subject: subject, kind: kind.to_s) }
      return existing if existing
    end

    ActsAsTenant.with_tenant(operator) { Conversion.create!(attrs) }
  rescue => e
    Rails.logger.error("Conversion.record failed (#{kind}): #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { kind: kind, user_id: user&.id, subject: subject&.class&.name }) if defined?(Honeybadger)
    nil
  end

  def amount
    amount_cents / 100.0
  end

  def revenue?
    REVENUE_KINDS.include?(kind)
  end
end
