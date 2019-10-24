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
end
