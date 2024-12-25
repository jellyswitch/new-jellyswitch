require 'rails_helper'

RSpec.describe Event, type: :model do
  let(:user) { create(:user) }
  let(:location) { create(:location) }
  let(:event) { create(:event, user: user, location: location) }

  describe 'associations' do
    it { should belong_to(:location) }
    it { should belong_to(:user) }
    it { should have_many(:rsvps) }
    it { should have_one_attached(:image) }
  end

  describe 'scopes' do
    let!(:future_event) { create(:event, starts_at: 1.day.from_now) }
    let!(:past_event) { create(:event, starts_at: 1.day.ago) }
    let!(:today_event) { create(:event, starts_at: Time.current) }

    describe '.future' do
      it 'returns events that start in the future' do
        expect(Event.future).to include(future_event)
        expect(Event.future).not_to include(past_event)
      end
    end

    describe '.past' do
      it 'returns events that started in the past' do
        expect(Event.past).to include(past_event)
        expect(Event.past).not_to include(future_event)
      end
    end

    describe '.today' do
      it 'returns events happening today' do
        expect(Event.today).to include(today_event)
        expect(Event.today).not_to include(future_event, past_event)
      end
    end
  end
end