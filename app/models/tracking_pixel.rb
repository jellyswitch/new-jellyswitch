# == Schema Information
#
# Table name: tracking_pixels
#
#  id            :bigint(8)        not null, primary key
#  name          :string
#  script        :string
#  position      :integer          default(0)
#  operator_id   :bigint(8)        not null
#  location_id   :bigint(8)        not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class TrackingPixel < ApplicationRecord
  include HasLocation

  acts_as_tenant :operator

  enum position: { head: 0, body: 1, footer: 2 }
end
