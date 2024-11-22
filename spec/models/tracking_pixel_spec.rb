require 'rails_helper'

RSpec.describe TrackingPixel, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:location).optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:position).with_values(head: 0, body: 1, footer: 2) }
  end
end