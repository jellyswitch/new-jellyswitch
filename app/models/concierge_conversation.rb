class ConciergeConversation < ApplicationRecord
  STATUSES = %w[open staffed captured closed].freeze

  # Minutes a visitor can wait on a staffer before the widget degrades to
  # capture ("the team's tied up — leave your email").
  STAFF_SLA_MINUTES = 5

  belongs_to :operator
  belongs_to :location, optional: true
  belongs_to :user, optional: true
  has_many :messages, -> { order(:created_at) }, class_name: "ConciergeMessage", dependent: :destroy

  acts_as_tenant :operator

  validates :session_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :ensure_token, on: :create

  # Staff hasn't replied AND the SLA window has elapsed → the widget should fall
  # back to capture so a busy floor never strands the visitor.
  def awaiting_staff_timeout?(now = Time.current)
    return false unless status == "open"
    return false if last_staff_message_at.present?
    (last_visitor_message_at || created_at) <= now - STAFF_SLA_MINUTES.minutes
  end

  private

  def ensure_token
    self.session_token ||= SecureRandom.urlsafe_base64(24)
  end
end
