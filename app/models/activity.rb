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
end
