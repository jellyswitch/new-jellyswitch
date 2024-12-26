require 'rails_helper'

RSpec.describe Announcement, type: :model do
  let(:operator) { create(:operator) }
  let(:user) { create(:user) }
  let(:location) { create(:location) }
  let(:announcement) { create(:announcement, operator: operator, user: user, location: location) }

  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:location).optional }
    it { should belong_to(:operator) }
  end

  describe 'concerns' do
    it 'includes HasLocation module' do
      expect(Announcement.ancestors).to include(HasLocation)
    end
  end

  describe 'scopes' do
    describe '.latest' do
      let!(:old_announcement) { create(:announcement, created_at: 2.days.ago) }
      let!(:new_announcement) { create(:announcement, created_at: 1.day.ago) }
      let!(:newest_announcement) { create(:announcement, created_at: 1.hour.ago) }

      it 'returns the most recent announcement' do
        expect(Announcement.latest).to eq(newest_announcement)
      end
    end
  end

  describe 'searchkick' do
    it 'has searchable attributes' do
      announcement = create(:announcement, body: 'Test announcement')
      search_data = announcement.search_data
      expect(search_data).to include(announcement: 'Test announcement')
    end
  end
end