# == Schema Information
#
# Table name: activities
#
#  id           :bigint(8)        not null, primary key
#  kind         :string           not null
#  occurred_at  :datetime         not null
#  payload      :jsonb            not null
#  subject_type :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  operator_id  :bigint(8)        not null
#  subject_id   :bigint(8)
#  user_id      :bigint(8)        not null
#
# Indexes
#
#  index_activities_on_operator_id_and_kind_and_occurred_at  (operator_id,kind,occurred_at)
#  index_activities_on_subject_type_and_subject_id           (subject_type,subject_id)
#  index_activities_on_user_id_and_occurred_at               (user_id,occurred_at)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => operators.id)
#  fk_rails_...  (user_id => users.id)
#
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

  after_create :assign_default_point_of_contact_on_tour
  after_create :notify_point_of_contact

  def self.log(**kwargs)
    ActivityLogger.log(**kwargs)
  end

  private

  def assign_default_point_of_contact_on_tour
    return unless kind.to_s == "tour"
    return if user.point_of_contact_id.present?
    user.assign_default_point_of_contact!
  end

  def notify_point_of_contact
    return unless Notifiable::PointOfContactAlert::SIGNIFICANT_KINDS.include?(kind.to_s)
    return unless user&.point_of_contact_id.present?
    SendNotificationsJob.perform_later(self, "PointOfContactAlert")
  end
end
