# == Schema Information
#
# Table name: announcements
#
#  id          :bigint(8)        not null, primary key
#  body        :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer
#  user_id     :integer
#
# Indexes
#
#  index_announcements_on_location_id  (location_id)
#

class Announcement < ApplicationRecord
  include HasLocation

  searchkick
  acts_as_tenant :operator
  belongs_to :user

  # Announcements auto-archive off the member-facing list this many days after
  # they're posted. "Archived" is virtual — the record is kept and stays visible
  # to staff via the admin API; it just stops showing to members. Bump this (or
  # move it to an operator setting) to change the window.
  ACTIVE_WINDOW_DAYS = 7

  scope :latest, -> { order("created_at DESC").first }
  scope :active, -> { where("announcements.created_at >= ?", ACTIVE_WINDOW_DAYS.days.ago) }
  scope :archived, -> { where("announcements.created_at < ?", ACTIVE_WINDOW_DAYS.days.ago) }

  def search_data
    {
      announcement: body,
      operator_id: operator_id,
    }
  end
end
