# == Schema Information
#
# Table name: rsvps
#
#  id         :bigint(8)        not null, primary key
#  going      :boolean          default(TRUE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  event_id   :integer          not null
#  user_id    :integer          not null
#

class Rsvp < ApplicationRecord
  belongs_to :event
  belongs_to :user

  scope :for_user, -> (user) { where(user_id: user.id) }
  scope :for_event, -> (event) { where(event_id: event.id) }
  scope :going, -> () { where(going: true) }
  scope :not_going, -> () { where(going: false) }

  def going?
    going == true
  end

  def not_going?
    going == false
  end
end
