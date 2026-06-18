# == Schema Information
#
# Table name: product_email_templates
#
#  id                   :bigint(8)        not null, primary key
#  email_type           :string           not null
#  enabled              :boolean          default(FALSE)
#  follow_up_delay_days :integer
#  product_type         :string           not null
#  subject              :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  location_id          :bigint(8)
#  operator_id          :bigint(8)        not null
#
# Indexes
#
#  idx_pet_operator_location_product_email       (operator_id,location_id,product_type,email_type) UNIQUE
#  index_product_email_templates_on_location_id  (location_id)
#  index_product_email_templates_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (operator_id => operators.id)
#
class ProductEmailTemplate < ApplicationRecord
  acts_as_tenant :operator
  belongs_to :operator
  belongs_to :location

  has_rich_text :body

  PRODUCT_TYPES = %w[day_pass day_pass_bundle reservation office_lease membership signup_nudge].freeze
  EMAIL_TYPES = %w[onboarding follow_up nudge re_engagement past_member_recovery replenishment].freeze

  # (product_type, email_type) combos that re_engagement and past_member_recovery
  # apply to. Onboarding/follow_up/nudge use the original cross-product matrix.
  RE_ENGAGEMENT_PRODUCTS = %w[day_pass reservation].freeze
  PAST_MEMBER_RECOVERY_PRODUCTS = %w[membership].freeze

  DEFAULT_SUBJECTS = {
    "day_pass_onboarding" => "Welcome! Here's what you need to know",
    "day_pass_follow_up" => "How was your visit?",
    "day_pass_re_engagement" => "Come back and see us",
    "day_pass_bundle_onboarding" => "Your pack is ready — here's how it works",
    "day_pass_bundle_follow_up" => "How was your visit?",
    "day_pass_bundle_replenishment" => "You're out of passes — grab another pack",
    "reservation_onboarding" => "Your reservation is confirmed!",
    "reservation_follow_up" => "How was your reservation?",
    "reservation_re_engagement" => "Ready for your next booking?",
    "office_lease_onboarding" => "Welcome to your new office!",
    "office_lease_follow_up" => "How's your office working out?",
    "membership_onboarding" => "Welcome, new member!",
    "membership_follow_up" => "How's your membership going?",
    "membership_past_member_recovery" => "We'd love to welcome you back",
    "signup_nudge_nudge" => "Come check us out!"
  }.freeze

  DEFAULT_DELAYS = {
    "day_pass" => 2,
    "day_pass_re_engagement" => 14,
    "reservation" => 1,
    "reservation_re_engagement" => 14,
    "office_lease" => 180,
    "membership" => 90,
    "membership_past_member_recovery" => 30,
    "signup_nudge" => 1
  }.freeze

  validates :product_type, presence: true, inclusion: { in: PRODUCT_TYPES }
  validates :email_type, presence: true, inclusion: { in: EMAIL_TYPES }
  validates :subject, presence: true
  validates :product_type, uniqueness: { scope: [:operator_id, :location_id, :email_type] }

  scope :onboarding, -> { where(email_type: "onboarding") }
  scope :follow_up, -> { where(email_type: "follow_up") }
  scope :nudge, -> { where(email_type: "nudge") }
  scope :re_engagement, -> { where(email_type: "re_engagement") }
  scope :past_member_recovery, -> { where(email_type: "past_member_recovery") }
  scope :replenishment, -> { where(email_type: "replenishment") }
  scope :enabled, -> { where(enabled: true) }
  scope :for_product, ->(type) { where(product_type: type) }
  scope :for_location, ->(location) { where(location: location) }

  before_save :disable_when_body_blank

  def self.seed_defaults_for(operator, location:)
    require Rails.root.join("db/seeds/welcome_drip_templates")

    # Product onboarding + follow-up
    %w[day_pass reservation office_lease membership].each do |product|
      %w[onboarding follow_up].each do |etype|
        delay = etype == "follow_up" ? DEFAULT_DELAYS[product] : nil
        seed_template(operator, location, product, etype, delay)
      end
    end

    # Day Pass Bundle lifecycle — event-fired (no time delay): onboarding on
    # purchase, follow_up (review) on first burn, replenishment at zero balance.
    # Bundles are NOT in RE_ENGAGEMENT_PRODUCTS (buyers are customers, not leads).
    %w[onboarding follow_up replenishment].each do |etype|
      seed_template(operator, location, "day_pass_bundle", etype, nil)
    end

    # Signup nudge
    seed_template(operator, location, "signup_nudge", "nudge", DEFAULT_DELAYS["signup_nudge"])

    # Re-engagement (day_passer_followup + room_reservation_followup automations)
    RE_ENGAGEMENT_PRODUCTS.each do |product|
      seed_template(operator, location, product, "re_engagement", DEFAULT_DELAYS["#{product}_re_engagement"])
    end

    # Past-member recovery (past_member_recovery automation)
    PAST_MEMBER_RECOVERY_PRODUCTS.each do |product|
      seed_template(operator, location, product, "past_member_recovery", DEFAULT_DELAYS["#{product}_past_member_recovery"])
    end
  end

  def self.seed_template(operator, location, product_type, email_type, delay_days = nil)
    template = find_or_create_by(operator: operator, location: location,
                                 product_type: product_type, email_type: email_type) do |t|
      subject_key = "#{product_type}_#{email_type}"
      t.subject = DEFAULT_SUBJECTS[subject_key] || "Email from #{operator.name}"
      t.follow_up_delay_days = delay_days
      t.enabled = false
    end

    # Only seed body on brand-new rows. Prefer copying a sibling location's
    # already-customized template over the brand-stripped default so a new
    # location inherits the operator's existing edits.
    if template.persisted? && template.body.blank?
      sibling = where(operator: operator, product_type: product_type, email_type: email_type)
                  .where.not(id: template.id)
                  .find { |t| t.body.present? }

      if sibling
        template.update!(body: sibling.body.to_s)
      else
        body_html = WelcomeDripSeed.body_for(product_type, email_type)
        template.update!(body: body_html) if body_html.present?
      end
    end

    template
  end

  def disable_when_body_blank
    self.enabled = false if body.blank?
  end

  def product_label
    case product_type
    when "day_pass" then "Day Pass"
    when "day_pass_bundle" then "Day Pass Bundle"
    when "reservation" then "Conference Room Reservation"
    when "office_lease" then "Office Lease"
    when "membership" then "Membership"
    when "signup_nudge" then "Signup Nudge"
    end
  end

  def email_type_label
    case email_type
    when "onboarding" then "Onboarding"
    when "follow_up" then "Follow-Up"
    when "nudge" then "Nudge"
    when "re_engagement" then "Re-Engagement"
    when "past_member_recovery" then "Past-Member Recovery"
    when "replenishment" then "Replenishment"
    end
  end

  def has_delay?
    # Bundle emails are event-fired (purchase / first burn / zero balance), so
    # none of them use a time delay.
    return false if product_type == "day_pass_bundle"

    email_type.in?(%w[follow_up nudge re_engagement past_member_recovery])
  end

  def delay_description
    if email_type == "re_engagement"
      "Days after the last visit with no return. The email fires only if the Person hasn't come back since."
    elsif email_type == "past_member_recovery"
      "Days after the past-member grace period ends. Tune the grace period in 'Stage transitions' above."
    else
      case product_type
      when "day_pass"
        "Days after the day pass date. Email sends at noon. Set to 0 to send midway through their visit day."
      when "reservation"
        "Days after the reservation ends. Set to 0 to send right after their booking."
      when "signup_nudge"
        "Days after signup to send if they haven't made a purchase."
      else
        "Days after purchase to send the follow-up email."
      end
    end
  end

  # Merge tags available for this template's product type
  def available_merge_tags
    tags = [
      { tag: "{{first_name}}", label: "First Name", description: "Member's first name" },
      { tag: "{{full_name}}", label: "Full Name", description: "Member's full name" },
      { tag: "{{space_name}}", label: "Space Name", description: "Location name" },
      { tag: "{{location_address}}", label: "Location Address", description: "Location's full address" },
      { tag: "{{location_phone}}", label: "Location Phone", description: "Location's contact phone" },
      { tag: "{{location_email}}", label: "Location Email", description: "Location's contact email" }
    ]

    case product_type
    when "day_pass"
      tags += [
        { tag: "{{date}}", label: "Date", description: "Day pass date" },
        { tag: "{{day_pass_type}}", label: "Day Pass Type", description: "Type of day pass" }
      ]
    when "day_pass_bundle"
      tags += [
        { tag: "{{quantity}}", label: "Pack Size", description: "Number of passes in the pack (e.g. 5)" },
        { tag: "{{passes_remaining}}", label: "Passes Remaining", description: "Passes left in the bundle right now" },
        { tag: "{{expires_at}}", label: "Expires", description: "Bundle expiration date (blank if it never expires)" },
        { tag: "{{day_pass_type}}", label: "Pack Type", description: "Name of the pack" }
      ]
    when "reservation"
      tags += [
        { tag: "{{date}}", label: "Date", description: "Reservation date" },
        { tag: "{{time}}", label: "Time", description: "Reservation start time" },
        { tag: "{{duration}}", label: "Duration", description: "Reservation duration" },
        { tag: "{{room_name}}", label: "Room Name", description: "Name of reserved room" }
      ]
    when "office_lease"
      tags += [
        { tag: "{{office_name}}", label: "Office Name", description: "Leased office name" },
        { tag: "{{start_date}}", label: "Start Date", description: "Lease start date" },
        { tag: "{{end_date}}", label: "End Date", description: "Lease end date" }
      ]
    when "membership"
      tags += [
        { tag: "{{plan_name}}", label: "Plan Name", description: "Membership plan name" },
        { tag: "{{start_date}}", label: "Start Date", description: "Membership start date" }
      ]
    end

    if email_type == "re_engagement"
      tags << { tag: "{{days_since_last_visit}}", label: "Days Since Last Visit", description: "Days since the Person's most recent visit" }
    end

    if email_type == "past_member_recovery"
      tags << { tag: "{{plan_canceled_on}}", label: "Plan Canceled On", description: "Date the Person's membership ended" }
    end

    if operator&.has_mobile_app_links?
      tags << { tag: "{{app_store_badge}}", label: "App Store Badge", description: "Apple App Store download badge with link" }
      tags << { tag: "{{play_store_badge}}", label: "Play Store Badge", description: "Google Play Store download badge with link" }
    end

    google_url = location&.effective_google_reviews_url || operator&.google_reviews_url
    if google_url.present?
      tags << { tag: "{{google_review_button}}", label: "Google Review Button", description: "Green button linking to your Google Reviews page" }
    end

    tags
  end

  # Replace merge tags in body content with actual values
  def self.replace_merge_tags(content, user:, operator:, location: nil, sendable: nil, host: nil)
    return content if content.blank?

    result = content.to_s

    # Universal tags
    first_name = user.name.to_s.split(" ").first || user.name.to_s
    result = result.gsub("{{first_name}}", first_name)
    result = result.gsub("{{full_name}}", user.name.to_s)
    result = result.gsub("{{space_name}}", location&.name || operator.name.to_s)

    # Location-specific tags
    if location
      result = result.gsub("{{location_address}}", location.full_address.to_s)
      result = result.gsub("{{location_phone}}", location.contact_phone.to_s)
      result = result.gsub("{{location_email}}", location.contact_email.to_s)
    end

    # App store badge tags
    if operator.has_mobile_app_links? && host.present?
      app_store_html = '<a href="' + operator.ios_url.to_s + '"><img src="' + ActionController::Base.helpers.asset_url('appstore.png', host: host) + '" width="135" height="40" alt="Download on the App Store" style="border: none;"></a>'
      play_store_html = '<a href="' + operator.android_url.to_s + '"><img src="' + ActionController::Base.helpers.asset_url('playstore.png', host: host) + '" width="135" height="40" alt="Get it on Google Play" style="border: none;"></a>'
      result = result.gsub("{{app_store_badge}}", app_store_html)
      result = result.gsub("{{play_store_badge}}", play_store_html)
    end

    # Google Review button tag
    google_url = location&.effective_google_reviews_url || operator.google_reviews_url
    if google_url.present?
      google_review_html = '<a href="' + google_url.to_s + '" target="_blank" style="display: inline-block; color: #ffffff; background-color: #27ae60; border: solid 1px #27ae60; border-radius: 4px; box-sizing: border-box; cursor: pointer; text-decoration: none; font-size: 14px; font-weight: bold; margin: 0; padding: 12px 24px;">Leave a Google Review</a>'
      result = result.gsub("{{google_review_button}}", google_review_html)
    end

    # Re-engagement: days since the user's most recent visit Activity.
    # Uses checkin/door_punch/reservation/day_pass kinds (per User::LIFECYCLE_VISIT_KINDS
    # extended to include day_pass).
    if result.include?("{{days_since_last_visit}}")
      last_visit = user.activities
                       .where(kind: %w[checkin door_punch reservation day_pass])
                       .maximum(:occurred_at)
      days = last_visit ? (Time.current.to_date - last_visit.to_date).to_i : nil
      result = result.gsub("{{days_since_last_visit}}", days&.to_s || "")
    end

    # Past-member recovery: when their most recent subscription ended.
    if result.include?("{{plan_canceled_on}}")
      ended_at = user.activities
                     .where(kind: "subscription_ended")
                     .maximum(:occurred_at)
      formatted = ended_at ? ended_at.to_date.strftime("%B %-d, %Y") : ""
      result = result.gsub("{{plan_canceled_on}}", formatted)
    end

    # Product-specific tags
    if sendable.present?
      case sendable
      when DayPass
        result = result.gsub("{{date}}", sendable.day&.strftime("%B %-d, %Y").to_s)
        result = result.gsub("{{day_pass_type}}", sendable.day_pass_type&.name.to_s)
      when DayPassBundle
        # A bundle has no single day, so {{date}} is intentionally left untouched.
        result = result.gsub("{{quantity}}", sendable.quantity_purchased.to_s)
        result = result.gsub("{{passes_remaining}}", sendable.passes_remaining.to_s)
        result = result.gsub("{{expires_at}}", sendable.expires_at&.strftime("%B %-d, %Y").to_s)
        result = result.gsub("{{day_pass_type}}", sendable.day_pass_type&.name.to_s)
      when Reservation
        result = result.gsub("{{date}}", sendable.datetime_in&.strftime("%B %-d, %Y").to_s)
        result = result.gsub("{{time}}", sendable.datetime_in&.strftime("%-I:%M %p").to_s)
        duration_mins = sendable.minutes
        duration_text = if duration_mins >= 60
          hours = duration_mins / 60
          mins = duration_mins % 60
          mins > 0 ? "#{hours}h #{mins}m" : "#{hours} #{"hour".pluralize(hours)}"
        else
          "#{duration_mins} minutes"
        end
        result = result.gsub("{{duration}}", duration_text)
        result = result.gsub("{{room_name}}", sendable.room&.name.to_s)
      when OfficeLease
        result = result.gsub("{{office_name}}", sendable.office&.name.to_s)
        result = result.gsub("{{start_date}}", sendable.start_date&.strftime("%B %-d, %Y").to_s)
        result = result.gsub("{{end_date}}", sendable.end_date&.strftime("%B %-d, %Y").to_s)
      when Subscription
        result = result.gsub("{{plan_name}}", sendable.plan&.name.to_s)
        result = result.gsub("{{start_date}}", sendable.start_date&.strftime("%B %-d, %Y").to_s)
      end
    end

    result
  end
end
