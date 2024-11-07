# == Schema Information
#
# Table name: location_managements
#
#  id                            :bigint(8)        not null, primary key
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :bigint(8)        not null
#  user_id                       :bigint(8)        not null
#
# Indexes
#
#  index_location_managements_on_location_id  (location_id)
#  index_location_managements_on_user_id      (user_id)
#

class LocationManagement < ApplicationRecord
  belongs_to :location
  belongs_to :user
end
