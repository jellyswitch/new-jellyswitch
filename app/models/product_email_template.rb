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
end
