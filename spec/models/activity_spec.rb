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
    it 'enumerates the Day-1 activity kinds from CONTEXT.md plus tour_request, chat, and office-queue outreach' do
      expect(Activity::KINDS).to contain_exactly(
        'signup', 'tour', 'tour_request', 'chat', 'checkin', 'door_punch', 'reservation', 'day_pass',
        'subscription_started', 'subscription_ended',
        'payment_succeeded', 'payment_failed',
        'note',
        'email_sent', 'email_opened', 'email_clicked', 'email_replied',
        'office_offered', 'office_declined'
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

      ids = [older.id, newest.id, middle.id]
      expect(Activity.where(id: ids).recent.to_a).to eq([newest, middle, older])
    end
  end

  describe "point-of-contact notification on after_create" do
    include ActiveJob::TestHelper

    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let!(:gm) { create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location) }
    let!(:person) { create(:user, operator: operator, current_location: location) }

    before { clear_enqueued_jobs }
    after { clear_enqueued_jobs }

    it "enqueues SendNotificationsJob with PointOfContactAlert when a significant Activity is logged for a PoC-owned Person" do
      expect {
        Activity.log(user: person, kind: :email_replied, operator: operator, subject: person)
      }.to have_enqueued_job(SendNotificationsJob).with(an_instance_of(Activity), "PointOfContactAlert")
    end

    it "enqueues for signup kind (creating a new user fires this end-to-end)" do
      expect {
        create(:user, operator: operator, current_location: location)
      }.to have_enqueued_job(SendNotificationsJob).with(an_instance_of(Activity), "PointOfContactAlert").once
    end

    it "does not enqueue for non-significant kinds" do
      expect {
        Activity.log(user: person, kind: :checkin, operator: operator, subject: person)
      }.not_to have_enqueued_job(SendNotificationsJob)
    end

    it "does not enqueue when the user has no point_of_contact" do
      orphan = create(:user, operator: operator, current_location: nil)
      orphan.update_column(:point_of_contact_id, nil)
      clear_enqueued_jobs
      expect {
        Activity.log(user: orphan, kind: :email_replied, operator: operator, subject: orphan)
      }.not_to have_enqueued_job(SendNotificationsJob)
    end

    it "uses the assigned point_of_contact as the sole recipient (not other team members)" do
      other_gm = create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location)
      activity = Activity.log(user: person, kind: :subscription_ended, operator: operator, subject: person)
      adapter = Notifiable::PointOfContactAlert.new(activity)
      expect(adapter.send(:recipients)).to contain_exactly(person.point_of_contact)
      expect(adapter.send(:recipients)).not_to include(other_gm)
    end
  end
end
