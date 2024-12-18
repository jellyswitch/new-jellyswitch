# spec/models/rsvp_spec.rb

require 'rails_helper'

RSpec.describe Rsvp, type: :model do
  describe 'associations' do
    it { should belong_to(:event) }
    it { should belong_to(:user) }
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let(:event) { create(:event) }
    let!(:going_rsvp) { create(:rsvp, user: user, event: event, going: true) }
    let!(:not_going_rsvp) { create(:rsvp, user: user, event: event, going: false) }

    describe '.for_user' do
      let(:other_user) { create(:user) }
      let!(:other_rsvp) { create(:rsvp, user: other_user, event: event) }

      it 'returns RSVPs for the specified user' do
        expect(Rsvp.for_user(user)).to include(going_rsvp, not_going_rsvp)
        expect(Rsvp.for_user(user)).not_to include(other_rsvp)
      end
    end

    describe '.for_event' do
      let(:other_event) { create(:event) }
      let!(:other_event_rsvp) { create(:rsvp, user: user, event: other_event) }

      it 'returns RSVPs for the specified event' do
        expect(Rsvp.for_event(event)).to include(going_rsvp, not_going_rsvp)
        expect(Rsvp.for_event(event)).not_to include(other_event_rsvp)
      end
    end

    describe '.today' do
      let(:today_event) { create(:event, starts_at: Time.current.noon) }
      let(:yesterday_event) { create(:event, starts_at: 1.day.ago.noon) }
      let(:tomorrow_event) { create(:event, starts_at: 1.day.from_now.noon) }

      let!(:today_rsvp) { create(:rsvp, event: today_event) }
      let!(:yesterday_rsvp) { create(:rsvp, event: yesterday_event) }
      let!(:tomorrow_rsvp) { create(:rsvp, event: tomorrow_event) }

      it 'returns RSVPs for events happening today' do
        expect(Rsvp.today).to include(today_rsvp)
        expect(Rsvp.today).not_to include(yesterday_rsvp, tomorrow_rsvp)
      end
    end

    describe '.going' do
      it 'returns RSVPs marked as going' do
        expect(Rsvp.going).to include(going_rsvp)
        expect(Rsvp.going).not_to include(not_going_rsvp)
      end
    end

    describe '.not_going' do
      it 'returns RSVPs marked as not going' do
        expect(Rsvp.not_going).to include(not_going_rsvp)
        expect(Rsvp.not_going).not_to include(going_rsvp)
      end
    end
  end

  describe 'instance methods' do
    describe '#going?' do
      it 'returns true when going is true' do
        rsvp = build(:rsvp, going: true)
        expect(rsvp.going?).to be true
      end

      it 'returns false when going is false' do
        rsvp = build(:rsvp, going: false)
        expect(rsvp.going?).to be false
      end
    end

    describe '#not_going?' do
      it 'returns true when going is false' do
        rsvp = build(:rsvp, going: false)
        expect(rsvp.not_going?).to be true
      end

      it 'returns false when going is true' do
        rsvp = build(:rsvp, going: true)
        expect(rsvp.not_going?).to be false
      end
    end
  end
end