# == Schema Information
#
# Table name: announcements
#
#  id          :bigint(8)        not null, primary key
#  body        :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer
#  location_id :integer
#  user_id     :integer
#

class Announcement < ApplicationRecord
  include HasLocation

  searchkick
  acts_as_tenant :operator
  belongs_to :user

  scope :latest, -> { order("created_at DESC").first }

  def search_data
    {
      announcement: body,
      operator_id: operator_id,
    }
  end
end
