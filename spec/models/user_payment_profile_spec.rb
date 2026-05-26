# == Schema Information
#
# Table name: user_payment_profiles
#
#  id                   :bigint(8)        not null, primary key
#  bill_to_organization :boolean          default(FALSE), not null
#  card_added           :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  location_id          :bigint(8)        not null
#  stripe_customer_id   :string
#  user_id              :bigint(8)        not null
#
# Indexes
#
#  index_user_payment_profiles_on_location_id              (location_id)
#  index_user_payment_profiles_on_user_id                  (user_id)
#  index_user_payment_profiles_on_user_id_and_location_id  (user_id,location_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (user_id => users.id)
#
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
