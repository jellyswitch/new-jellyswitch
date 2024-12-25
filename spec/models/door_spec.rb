require 'rails_helper'

RSpec.describe Door, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location) }
  let(:door) { create(:door, operator: operator, location: location) }

  describe 'associations' do
    it { should have_many(:door_punches).dependent(:destroy) }
    it { should belong_to(:operator) }
    it { should belong_to(:location) }
  end

  describe 'friendly_id' do
    it 'generates slug from name' do
      door = create(:door, name: 'Test Door', slug: nil)
      expect(door.slug).to eq('test-door')
    end

    it 'generates unique slugs' do
      door1 = create(:door, name: 'Test Door')
      door2 = create(:door, name: 'Test Door')
      expect(door2.slug).not_to eq(door1.slug)
    end
  end

  describe 'searchkick' do
    it 'has searchable attributes' do
      search_data = door.search_data
      expect(search_data).to include(name: door.name)
    end
  end

  describe 'defaults' do
    it 'sets available to true by default' do
      door = Door.new
      expect(door.available).to be true
    end

    it 'sets operator_id to 1 by default' do
      door = Door.new
      expect(door.operator_id).to eq(1)
    end
  end
end