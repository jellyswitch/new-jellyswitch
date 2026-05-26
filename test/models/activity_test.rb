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
  test "tour_request is a valid Activity kind" do
    user = users(:cowork_tahoe_member)
    operator = user.operator
    activity = Activity.new(user: user, operator: operator, kind: :tour_request, occurred_at: Time.current, payload: {})
    assert activity.valid?, activity.errors.full_messages.inspect
  end
end
