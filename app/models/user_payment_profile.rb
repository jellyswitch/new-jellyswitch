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

class UserPaymentProfile < ApplicationRecord
  belongs_to :user
  belongs_to :location

  validates :user_id, uniqueness: { scope: :location_id }
end
