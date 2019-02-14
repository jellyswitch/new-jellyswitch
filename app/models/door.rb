# == Schema Information
#
# Table name: doors
#
#  id          :bigint(8)        not null, primary key
#  name        :string           not null
#  slug        :string           not null
#  available   :boolean          default(TRUE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          default(1), not null
#

class Door < ApplicationRecord
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Relationships
  has_many :door_punches
  belongs_to :operator
  acts_as_tenant :operator
end
