# == Schema Information
#
# Table name: user_payment_profiles
#
#  id                            :bigint(8)        not null, primary key
#  user_id                       :bigint(8)        not null
#  location_id                   :bigint(8)        not null
#  stripe_customer_id            :string
#  card_added                    :boolean          default(FALSE), not null
#  bill_to_organization          :boolean          default(FALSE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_user_payment_profiles_on_user_id_and_location_id  (user_id,location_id) UNIQUE
#

class UserPaymentProfile < ApplicationRecord
  belongs_to :user
  belongs_to :location

  validates :user_id, uniqueness: { scope: :location_id }
end