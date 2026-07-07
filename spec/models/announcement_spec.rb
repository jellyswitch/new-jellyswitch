# == Schema Information
#
# Table name: announcements
#
#  id          :bigint(8)        not null, primary key
#  body        :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer
#  user_id     :integer
#
# Indexes
#
#  index_announcements_on_location_id  (location_id)
#
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

    describe '.active' do
      let!(:fresh) { create(:announcement, created_at: 6.days.ago) }
      let!(:stale) { create(:announcement, created_at: 8.days.ago) }

      it 'includes announcements posted within the last ACTIVE_WINDOW_DAYS days' do
        expect(Announcement.active).to include(fresh)
      end

      it 'excludes announcements older than ACTIVE_WINDOW_DAYS days' do
        expect(Announcement.active).not_to include(stale)
      end
    end

    describe '.archived' do
      let!(:fresh) { create(:announcement, created_at: 6.days.ago) }
      let!(:stale) { create(:announcement, created_at: 8.days.ago) }

      it 'is the complement of .active' do
        expect(Announcement.archived).to include(stale)
        expect(Announcement.archived).not_to include(fresh)
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
