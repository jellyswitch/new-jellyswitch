# == Schema Information
#
# Table name: tracking_pixels
#
#  id          :bigint(8)        not null, primary key
#  always_on   :boolean          default(FALSE), not null
#  name        :string
#  position    :integer          default("head")
#  script      :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :bigint(8)        not null
#  operator_id :bigint(8)        not null
#
# Indexes
#
#  index_tracking_pixels_on_location_id  (location_id)
#  index_tracking_pixels_on_operator_id  (operator_id)
#  index_tracking_pixels_on_position     (position)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (operator_id => operators.id)
#
FactoryBot.define do
  factory :tracking_pixel do
    name { "Google Analytics" }
    script { "UA-12345678-1" }
    position { :body }
    association :operator
    association :location
  end
end
