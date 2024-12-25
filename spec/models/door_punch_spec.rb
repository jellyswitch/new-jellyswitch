require 'rails_helper'

RSpec.describe DoorPunch, type: :model do
  let(:operator) { create(:operator) }
  let(:user) { create(:user) }
  let(:door) { create(:door) }
  let(:door_punch) { create(:door_punch, operator: operator, user: user, door: door) }

  describe 'associations' do
    it { should belong_to(:door) }
    it { should belong_to(:user) }
    it { should belong_to(:operator) }
  end

  describe 'scopes' do
    describe '.this_month' do
      let!(:this_month_punch) { create(:door_punch, created_at: Time.current) }
      let!(:last_month_punch) { create(:door_punch, created_at: 1.month.ago) }

      it 'returns punches from current month' do
        expect(DoorPunch.this_month).to include(this_month_punch)
        expect(DoorPunch.this_month).not_to include(last_month_punch)
      end
    end
  end

  describe '#pretty_datetime' do
    it 'formats the datetime correctly' do
      door_punch = create(:door_punch, created_at: Time.zone.local(2024, 1, 15, 14, 30))
      expect(door_punch.pretty_datetime).to eq('01/15/2024 at  2:30pm')
    end
  end

  describe 'defaults' do
    it 'sets operator_id to 1 by default' do
      door_punch = DoorPunch.new
      expect(door_punch.operator_id).to eq(1)
    end
  end

  describe 'json attribute' do
    it 'stores and retrieves json data' do
      json_data = { "key" => "value" }
      door_punch = create(:door_punch, json: json_data)
      expect(door_punch.reload.json).to eq(json_data)
    end
  end
end