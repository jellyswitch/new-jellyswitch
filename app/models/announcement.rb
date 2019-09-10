# == Schema Information
#
# Table name: announcements
#
#  id          :bigint(8)        not null, primary key
#  body        :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer
#  user_id     :integer
#

class Announcement < ApplicationRecord
  belongs_to :operator
  belongs_to :user

  scope :latest, -> { order("created_at DESC").first }
end
