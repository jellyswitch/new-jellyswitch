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
    tour_request
    chat
    checkin
    door_punch
    reservation
    day_pass
    day_pass_bundle
    admin_action
    subscription_started
    subscription_ended
    office_lease
    payment_succeeded
    payment_failed
    note
    email_sent
    email_opened
    email_clicked
    email_replied
    office_offered
    office_declined
  ].freeze

  belongs_to :user
  belongs_to :operator
  belongs_to :subject, polymorphic: true, optional: true

  acts_as_tenant :operator

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }

  after_create :assign_default_point_of_contact_on_tour
  # after_create_commit (not after_create): the alert enqueues a Sidekiq job
  # that reloads this Activity by GlobalID. Activities are logged from inside
  # other models' transactions (User#log_signup_activity,
  # Subscription#log_subscription_ended_if_deactivated, ...), so enqueuing in
  # after_create pushed the job to Redis before the surrounding transaction
  # committed — a worker could deserialize Activity.find(id) before the row was
  # visible, or after a rollback, raising ActiveJob::DeserializationError.
  # Deferring to commit guarantees the row exists and skips the enqueue entirely
  # on rollback.
  after_create_commit :notify_point_of_contact

  def self.log(**kwargs)
    ActivityLogger.log(**kwargs)
  end

  # Audit trail for account-state changes (archive/unarchive/approve/
  # unapprove/self-delete). Born from a five-day mystery: someone archived
  # the Cowork Tahoe space host's account via the mobile admin app on
  # 2026-08-14 and NOTHING recorded who — no actor, no timestamp beyond the
  # row's updated_at. These land on the affected member's timeline as
  # "Archived by <actor>". Failures never block the admin action itself.
  def self.log_admin_action(user:, actor:, operator:, action:)
    log(
      user: user,
      operator: operator,
      kind: :admin_action,
      payload: {
        "action" => action.to_s,
        "actor_id" => actor&.id,
        "actor_name" => actor&.name,
      },
    )
  rescue => e
    Rails.logger.error("log_admin_action failed: #{e.message}")
    nil
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
