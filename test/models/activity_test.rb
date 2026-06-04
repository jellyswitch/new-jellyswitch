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
require 'test_helper'

class ActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "tour_request is a valid Activity kind" do
    user = users(:cowork_tahoe_member)
    operator = user.operator
    activity = Activity.new(user: user, operator: operator, kind: :tour_request, occurred_at: Time.current, payload: {})
    assert activity.valid?, activity.errors.full_messages.inspect
  end

  # The point-of-contact alert enqueues SendNotificationsJob, which reloads the
  # Activity by GlobalID. It must fire only AFTER the transaction commits, or a
  # Sidekiq worker can run Activity.find before the row is visible / after a
  # rollback -> ActiveJob::DeserializationError in production.
  test "significant Activity enqueues the point-of-contact alert after commit" do
    user = users(:cowork_tahoe_member)
    user.update_column(:point_of_contact_id, users(:cowork_tahoe_admin).id)

    assert_enqueued_with(job: SendNotificationsJob) do
      Activity.create!(user: user, operator: user.operator, kind: :subscription_ended,
                       occurred_at: Time.current, payload: {})
    end
  end

  test "does NOT enqueue the alert when the surrounding transaction rolls back" do
    user = users(:cowork_tahoe_member)
    user.update_column(:point_of_contact_id, users(:cowork_tahoe_admin).id)

    assert_no_enqueued_jobs only: SendNotificationsJob do
      ActiveRecord::Base.transaction do
        Activity.create!(user: user, operator: user.operator, kind: :subscription_ended,
                         occurred_at: Time.current, payload: {})
        raise ActiveRecord::Rollback
      end
    end
  end
end
