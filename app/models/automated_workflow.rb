class AutomatedWorkflow < ApplicationRecord
  belongs_to :operator
  belongs_to :location, optional: true

  acts_as_tenant :operator

  TYPES = %w[re_engagement past_due_followup booking_reminder signup_nurture].freeze

  DEFAULT_CONFIGS = {
    "re_engagement" => { "days_inactive" => 14 },
    "past_due_followup" => { "followup_days" => [3, 7, 14] },
    "booking_reminder" => { "hours_before" => 24 },
    "signup_nurture" => { "sequence_days" => [1, 3, 7, 14] },
  }.freeze

  validates :workflow_type, presence: true, inclusion: { in: TYPES }
  validates :workflow_type, uniqueness: { scope: [:operator_id, :location_id] }

  def self.seed_defaults_for(operator, location:)
    TYPES.each do |type|
      find_or_create_by!(operator: operator, location: location, workflow_type: type) do |w|
        w.enabled = false
        w.config = DEFAULT_CONFIGS[type]
      end
    end
  end

  def days_inactive
    config["days_inactive"] || 14
  end

  def followup_days
    config["followup_days"] || [3, 7, 14]
  end

  def hours_before
    config["hours_before"] || 24
  end

  def sequence_days
    config["sequence_days"] || [1, 3, 7, 14]
  end

  def human_name
    case workflow_type
    when "re_engagement" then "Re-engagement"
    when "past_due_followup" then "Past-due follow-up"
    when "booking_reminder" then "Booking reminder"
    when "signup_nurture" then "Signup nurture drip"
    end
  end

  def description
    case workflow_type
    when "re_engagement"
      "Email members who haven't booked a room or used their door key in #{days_inactive} days"
    when "past_due_followup"
      "Send follow-up emails at day #{followup_days.join(', ')} for unpaid invoices"
    when "booking_reminder"
      "Email reminder 24 hours before paid room reservations. Push notification 10 min before all reservations."
    when "signup_nurture"
      "4-step drip for new signups who haven't purchased: day #{sequence_days.join(', ')}"
    end
  end
end
