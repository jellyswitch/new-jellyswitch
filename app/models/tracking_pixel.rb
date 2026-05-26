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

class TrackingPixel < ApplicationRecord
  include HasLocation

  acts_as_tenant :operator

  enum position: { head: 0, body: 1, footer: 2 }

  scope :always_on, -> { where(always_on: true) }
  scope :conversion_only, -> { where(always_on: false) }
end
