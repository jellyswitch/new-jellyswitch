require 'rails_helper'

RSpec.describe Lead, type: :model do
  describe 'associations' do
    it { should belong_to(:operator) }
    it { should belong_to(:user) }
    it { should belong_to(:ahoy_visit).class_name('Ahoy::Visit') }
    it { should have_many(:lead_notes) }
  end

  describe 'constants' do
    it 'defines SOURCES' do
      expect(Lead::SOURCES).to eq({
        web: "web",
        event: "event",
        referral: "referral"
      })
    end

    it 'defines STATUSES' do
      expect(Lead::STATUSES).to eq({
        open: "open",
        closed_lost: "closed-lost",
        closed_won: "closed-won"
      })
    end
  end

  describe 'callbacks' do
    let(:user) { create(:user) }
    let(:operator) { create(:operator) }

    describe '#set_status' do
      context 'when status is blank' do
        let(:lead) { build(:lead, user: user, operator: operator, status: nil) }

        it 'sets default status to open' do
          lead.save
          expect(lead.reload.status).to eq(Lead::STATUSES[:open])
        end
      end

      context 'when status is present' do
        let(:lead) { build(:lead, user: user, operator: operator, status: Lead::STATUSES[:closed_won]) }

        it 'keeps the existing status' do
          lead.save
          expect(lead.reload.status).to eq(Lead::STATUSES[:closed_won])
        end
      end
    end

    describe '#set_source' do
      context 'when source is blank and ahoy_visit is present' do
        let(:ahoy_visit) { create(:ahoy_visit) }
        let(:lead) { build(:lead, user: user, operator: operator, source: nil, ahoy_visit: ahoy_visit) }

        it 'sets source to web' do
          lead.save
          expect(lead.reload.source).to eq(Lead::SOURCES[:web])
        end
      end

      context 'when source is present' do
        let(:lead) { build(:lead, user: user, operator: operator, source: Lead::SOURCES[:event]) }

        it 'keeps the existing source' do
          lead.save
          expect(lead.reload.source).to eq(Lead::SOURCES[:event])
        end
      end
    end
  end

  describe '#gravatar' do
    let(:user) { create(:user, email: 'test@example.com') }
    let(:lead) { create(:lead, user: user, operator: create(:operator)) }
    let(:expected_hash) { Digest::MD5.hexdigest('test@example.com') }

    it 'returns the correct gravatar URL' do
      expect(lead.gravatar).to eq("https://www.gravatar.com/avatar/#{expected_hash}")
    end
  end
end