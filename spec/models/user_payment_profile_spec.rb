require "rails_helper"

RSpec.describe UserPaymentProfile, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:location) }
  end

  describe "validations" do
    subject { create(:user_payment_profile) }
    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:location_id) }
  end
end