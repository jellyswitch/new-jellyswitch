class ProductEmailTemplate < ApplicationRecord
  acts_as_tenant :operator
  belongs_to :operator

  has_rich_text :body

  PRODUCT_TYPES = %w[day_pass reservation office_lease membership signup_nudge].freeze
  EMAIL_TYPES = %w[onboarding follow_up nudge].freeze

  DEFAULT_SUBJECTS = {
    "day_pass_onboarding" => "Welcome! Here's what you need to know",
    "day_pass_follow_up" => "How was your visit?",
    "reservation_onboarding" => "Your reservation is confirmed!",
    "reservation_follow_up" => "How was your reservation?",
    "office_lease_onboarding" => "Welcome to your new office!",
    "office_lease_follow_up" => "How's your office working out?",
    "membership_onboarding" => "Welcome, new member!",
    "membership_follow_up" => "How's your membership going?",
    "signup_nudge_nudge" => "Come check us out!"
  }.freeze

  DEFAULT_DELAYS = {
    "day_pass" => 2,
    "reservation" => 1,
    "office_lease" => 180,
    "membership" => 90,
    "signup_nudge" => 1
  }.freeze

  validates :product_type, presence: true, inclusion: { in: PRODUCT_TYPES }
  validates :email_type, presence: true, inclusion: { in: EMAIL_TYPES }
  validates :subject, presence: true
  validates :product_type, uniqueness: { scope: [:operator_id, :email_type] }

  scope :onboarding, -> { where(email_type: "onboarding") }
  scope :follow_up, -> { where(email_type: "follow_up") }
  scope :nudge, -> { where(email_type: "nudge") }
  scope :enabled, -> { where(enabled: true) }
  scope :for_product, ->(type) { where(product_type: type) }

  def self.seed_defaults_for(operator)
    # Product onboarding + follow-up
    %w[day_pass reservation office_lease membership].each do |product|
      %w[onboarding follow_up].each do |etype|
        find_or_create_by(operator: operator, product_type: product, email_type: etype) do |t|
          t.subject = DEFAULT_SUBJECTS["#{product}_#{etype}"] || "Email from #{operator.name}"
          t.follow_up_delay_days = DEFAULT_DELAYS[product] if etype == "follow_up"
          t.enabled = false
        end
      end
    end

    # Signup nudge
    find_or_create_by(operator: operator, product_type: "signup_nudge", email_type: "nudge") do |t|
      t.subject = DEFAULT_SUBJECTS["signup_nudge_nudge"] || "Come check us out!"
      t.follow_up_delay_days = DEFAULT_DELAYS["signup_nudge"]
      t.enabled = false
    end
  end

  def product_label
    case product_type
    when "day_pass" then "Day Pass"
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
    end
  end

  def has_delay?
    email_type.in?(%w[follow_up nudge])
  end

  # Merge tags available for this template's product type
  def available_merge_tags
    tags = [
      { tag: "{{first_name}}", label: "First Name", description: "Member's first name" },
      { tag: "{{full_name}}", label: "Full Name", description: "Member's full name" },
      { tag: "{{space_name}}", label: "Space Name", description: "Your coworking space name" }
    ]

    case product_type
    when "day_pass"
      tags += [
        { tag: "{{date}}", label: "Date", description: "Day pass date" },
        { tag: "{{day_pass_type}}", label: "Day Pass Type", description: "Type of day pass" }
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

    tags
  end

  # Replace merge tags in body content with actual values
  def self.replace_merge_tags(content, user:, operator:, sendable: nil)
    return content if content.blank?

    result = content.to_s

    # Universal tags
    first_name = user.name.to_s.split(" ").first || user.name.to_s
    result = result.gsub("{{first_name}}", first_name)
    result = result.gsub("{{full_name}}", user.name.to_s)
    result = result.gsub("{{space_name}}", operator.name.to_s)

    # Product-specific tags
    if sendable.present?
      case sendable
      when DayPass
        result = result.gsub("{{date}}", sendable.day&.strftime("%B %-d, %Y").to_s)
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
