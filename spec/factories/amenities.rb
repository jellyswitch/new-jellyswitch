# == Schema Information
#
# Table name: amenities
#
#  id               :bigint(8)        not null, primary key
#  membership_price :float            default(0.0)
#  name             :string
#  price            :float            default(0.0)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  room_id          :bigint(8)        not null
#
# Indexes
#
#  index_amenities_on_room_id  (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (room_id => rooms.id)
#
FactoryBot.define do
  factory :amenity do
    sequence(:name) { |n| "Amenity #{n}" }
    price { Faker::Number.between(from: 10.0, to: 25.0) }
    membership_price { Faker::Number.between(from: 0, to: 10.0) }

    association :room
  end
end
