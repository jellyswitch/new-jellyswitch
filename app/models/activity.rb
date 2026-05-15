class Activity < ApplicationRecord
  KINDS = %w[
    signup
    tour
    checkin
    door_punch
    reservation
    day_pass
    subscription_started
    subscription_ended
    payment_succeeded
    payment_failed
    note
    email_sent
    email_opened
    email_clicked
    email_replied
  ].freeze

  belongs_to :user
  belongs_to :operator
  belongs_to :subject, polymorphic: true, optional: true

  acts_as_tenant :operator

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
end
