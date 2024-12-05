require 'rails_helper'

RSpec.describe DayPass, type: :model do
  describe 'associations' do
    it { should belong_to(:billable) }
    it { should belong_to(:day_pass_type) }
    it { should belong_to(:invoice).optional }
    it { should belong_to(:user) }
    it { should belong_to(:operator) }
  end

  describe 'scopes' do
    let!(:today_pass) { create(:day_pass, day: Time.current) }
    let!(:yesterday_pass) { create(:day_pass, day: 1.day.ago) }
    let!(:old_pass) { create(:day_pass, day: 40.days.ago) }
    let!(:this_month_pass) { create(:day_pass, day: Time.current.beginning_of_month + 1.day) }
    let!(:last_month_pass) { create(:day_pass, day: Time.current.beginning_of_month - 1.day) }

    describe '.today' do
      it 'returns day passes for current day' do
        expect(DayPass.today).to include(today_pass)
        expect(DayPass.today).not_to include(yesterday_pass)
      end
    end

    describe '.for_day' do
      it 'returns day passes for specific date' do
        specific_date = Time.current.to_date
        expect(DayPass.for_day(specific_date)).to include(today_pass)
        expect(DayPass.for_day(specific_date)).not_to include(yesterday_pass)
      end
    end

    describe '.last_30_days' do
      it 'returns day passes from last 30 days' do
        expect(DayPass.last_30_days).to include(today_pass, yesterday_pass)
        expect(DayPass.last_30_days).not_to include(old_pass)
      end
    end

    describe '.this_month' do
      it 'returns day passes from current month' do
        expect(DayPass.this_month).to include(this_month_pass)
        expect(DayPass.this_month).not_to include(last_month_pass)
      end
    end

    describe '.for_week' do
      it 'returns day passes within specified week range' do
        week_start = 1.week.ago
        week_end = Time.current
        pass_in_range = create(:day_pass, day: 3.days.ago)
        pass_out_of_range = create(:day_pass, day: 2.weeks.ago)

        expect(DayPass.for_week(week_start, week_end)).to include(pass_in_range)
        expect(DayPass.for_week(week_start, week_end)).not_to include(pass_out_of_range)
      end
    end
  end

  describe 'instance methods' do
    let(:operator) { create(:operator, name: 'Test Operator') }
    let(:day_pass) { create(:day_pass, operator: operator, day: Date.new(2024, 1, 1)) }
    let(:day_pass_type) { create(:day_pass_type, name: 'Standard Pass') }

    describe '#pretty_day' do
      it 'returns formatted date string' do
        expect(day_pass.pretty_day).to eq('01/01/2024')
      end
    end

    describe '#charge_description' do
      it 'returns formatted charge description' do
        expected_description = "Test Operator Day Pass for 01/01/2024"
        expect(day_pass.charge_description).to eq(expected_description)
      end
    end

    describe '#today?' do
      it 'returns true for today\'s pass' do
        today_pass = create(:day_pass, day: Time.zone.today)
        expect(today_pass.today?).to be true
      end

      it 'returns false for other day\'s pass' do
        other_day_pass = create(:day_pass, day: 1.day.ago)
        expect(other_day_pass.today?).to be false
      end
    end

    describe '#day_pass_type_name' do
      it 'returns day pass type name when present' do
        day_pass.day_pass_type = day_pass_type
        expect(day_pass.day_pass_type_name).to eq('Standard Pass')
      end

      it 'returns "Unknown" when day pass type is not present' do
        day_pass.day_pass_type = nil
        expect(day_pass.day_pass_type_name).to eq('Unknown')
      end
    end

    describe '#subscribable' do
      it 'returns the associated user' do
        user = create(:user)
        day_pass.user = user
        expect(day_pass.subscribable).to eq(user)
      end
    end
  end
end