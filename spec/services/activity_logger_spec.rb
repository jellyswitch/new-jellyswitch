require 'rails_helper'

RSpec.describe ActivityLogger, type: :service do
  let(:operator) { create(:operator) }
  let(:user)     { create(:user) }

  describe '.log' do
    it 'creates and returns a persisted Activity with the given attrs' do
      activity = ActivityLogger.log(user: user, operator: operator, kind: 'signup')

      expect(activity).to be_a(Activity)
      expect(activity).to be_persisted
      expect(activity.user).to eq(user)
      expect(activity.operator).to eq(operator)
      expect(activity.kind).to eq('signup')
    end

    it 'accepts kind as a symbol and stores it as a string' do
      activity = ActivityLogger.log(user: user, operator: operator, kind: :signup)
      expect(activity.kind).to eq('signup')
    end

    it 'raises RecordInvalid when kind is not in Activity::KINDS' do
      expect {
        ActivityLogger.log(user: user, operator: operator, kind: 'not_a_kind')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    describe 'occurred_at' do
      it 'defaults to Time.current when not given' do
        before = Time.current
        activity = ActivityLogger.log(user: user, operator: operator, kind: 'signup')
        after  = Time.current

        expect(activity.occurred_at).to be_between(before, after)
      end

      it 'uses an explicit occurred_at when provided (backfill case)' do
        then_time = 3.days.ago.change(usec: 0)
        activity = ActivityLogger.log(
          user: user, operator: operator, kind: 'reservation',
          occurred_at: then_time
        )
        expect(activity.occurred_at).to eq(then_time)
      end
    end

    describe 'payload' do
      it 'persists an explicit payload as-is when given' do
        activity = ActivityLogger.log(
          user: user, operator: operator, kind: 'tour',
          payload: { 'notes' => 'walk-in', 'logged_by_user_id' => 99 }
        )
        expect(activity.payload).to eq('notes' => 'walk-in', 'logged_by_user_id' => 99)
      end

      it 'defaults to {} when no payload given and no subject' do
        activity = ActivityLogger.log(user: user, operator: operator, kind: 'tour')
        expect(activity.payload).to eq({})
      end

      it 'defaults to {} when subject is present but does not declare to_activity_payload' do
        lead = create(:lead, user: user, operator: operator)
        activity = ActivityLogger.log(
          user: user, operator: operator, kind: 'note', subject: lead
        )
        expect(activity.payload).to eq({})
      end

      it 'denormalizes via subject#to_activity_payload when payload omitted' do
        lead = create(:lead, user: user, operator: operator)
        lead.define_singleton_method(:to_activity_payload) do
          { 'source' => source, 'status' => status }
        end

        activity = ActivityLogger.log(
          user: user, operator: operator, kind: 'note', subject: lead
        )
        expect(activity.payload).to eq('source' => 'web', 'status' => 'open')
      end

      it 'does NOT call to_activity_payload when explicit payload is given' do
        lead = create(:lead, user: user, operator: operator)
        lead.define_singleton_method(:to_activity_payload) do
          raise 'to_activity_payload should not be called when payload is explicit'
        end

        activity = ActivityLogger.log(
          user: user, operator: operator, kind: 'note', subject: lead,
          payload: { 'explicit' => true }
        )
        expect(activity.payload).to eq('explicit' => true)
      end
    end

    describe 'operator derivation' do
      it 'derives operator from subject.operator when operator: not given' do
        lead = create(:lead, user: user, operator: operator)
        activity = ActivityLogger.log(user: user, kind: 'note', subject: lead)
        expect(activity.operator).to eq(operator)
      end

      it 'raises ArgumentError when operator cannot be derived' do
        expect {
          ActivityLogger.log(user: user, kind: 'tour')
        }.to raise_error(ArgumentError, /operator/)
      end
    end

    describe 'polymorphic subject' do
      it 'sets subject_type and subject_id from the passed subject' do
        lead = create(:lead, user: user, operator: operator)
        activity = ActivityLogger.log(
          user: user, operator: operator, kind: 'note', subject: lead
        )
        expect(activity.subject).to eq(lead)
        expect(activity.subject_type).to eq('Lead')
        expect(activity.subject_id).to eq(lead.id)
      end
    end
  end
end

RSpec.describe Activity, type: :model do
  describe '.log convenience class method' do
    let(:operator) { create(:operator) }
    let(:user)     { create(:user) }

    it 'delegates to ActivityLogger.log and returns the Activity' do
      activity = Activity.log(user: user, operator: operator, kind: 'signup')
      expect(activity).to be_a(Activity)
      expect(activity).to be_persisted
    end

    it 'forwards all kwargs to ActivityLogger' do
      lead = create(:lead, user: user, operator: operator)
      expect(ActivityLogger).to receive(:log).with(
        user: user, operator: operator, kind: :note, subject: lead, payload: { 'k' => 1 }
      ).and_call_original

      Activity.log(user: user, operator: operator, kind: :note, subject: lead, payload: { 'k' => 1 })
    end
  end
end
