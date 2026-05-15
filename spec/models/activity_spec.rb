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
require 'rails_helper'

RSpec.describe Activity, type: :model do
  let(:user)     { create(:user) }
  let(:operator) { create(:operator) }

  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:operator) }
  end

  describe 'KINDS' do
    it 'enumerates the 15 Day-1 activity kinds from CONTEXT.md' do
      expect(Activity::KINDS).to contain_exactly(
        'signup', 'tour', 'checkin', 'door_punch', 'reservation', 'day_pass',
        'subscription_started', 'subscription_ended',
        'payment_succeeded', 'payment_failed',
        'note',
        'email_sent', 'email_opened', 'email_clicked', 'email_replied'
      )
    end
  end

  describe 'validations' do
    it 'requires a kind' do
      activity = Activity.new(user: user, operator: operator, occurred_at: Time.current)
      expect(activity).not_to be_valid
      expect(activity.errors[:kind]).to be_present
    end

    it 'rejects a kind not in KINDS' do
      activity = Activity.new(user: user, operator: operator, kind: 'bogus', occurred_at: Time.current)
      expect(activity).not_to be_valid
      expect(activity.errors[:kind].join).to match(/not included/)
    end

    it 'accepts every kind in KINDS' do
      Activity::KINDS.each do |kind|
        activity = Activity.new(user: user, operator: operator, kind: kind, occurred_at: Time.current)
        expect(activity).to be_valid, "expected kind #{kind} to be valid, got #{activity.errors.full_messages.inspect}"
      end
    end

    it 'requires occurred_at' do
      activity = Activity.new(user: user, operator: operator, kind: 'signup')
      expect(activity).not_to be_valid
      expect(activity.errors[:occurred_at]).to be_present
    end
  end

  describe 'payload' do
    it 'defaults to an empty hash' do
      activity = Activity.create!(user: user, operator: operator, kind: 'signup', occurred_at: Time.current)
      expect(activity.payload).to eq({})
    end

    it 'round-trips arbitrary jsonb data' do
      activity = Activity.create!(
        user: user, operator: operator, kind: 'tour',
        payload: { 'notes' => 'walked in cold', 'logged_by_user_id' => 42 },
        occurred_at: Time.current
      )
      expect(activity.reload.payload).to eq('notes' => 'walked in cold', 'logged_by_user_id' => 42)
    end
  end

  describe 'polymorphic subject' do
    it 'is optional (manually-logged tours have no subject)' do
      activity = Activity.new(user: user, operator: operator, kind: 'tour', occurred_at: Time.current)
      expect(activity).to be_valid
    end

    it 'can reference any model via subject_type + subject_id' do
      activity = Activity.create!(
        user: user, operator: operator, kind: 'signup',
        subject: user, occurred_at: Time.current
      )
      expect(activity.reload.subject).to eq(user)
      expect(activity.subject_type).to eq('User')
      expect(activity.subject_id).to eq(user.id)
    end
  end

  describe '.recent scope' do
    it 'orders activities by occurred_at descending' do
      older  = Activity.create!(user: user, operator: operator, kind: 'signup',   occurred_at: 3.days.ago)
      newest = Activity.create!(user: user, operator: operator, kind: 'tour',     occurred_at: 1.hour.ago)
      middle = Activity.create!(user: user, operator: operator, kind: 'checkin',  occurred_at: 1.day.ago)

      expect(Activity.recent.to_a).to eq([newest, middle, older])
    end
  end
end
