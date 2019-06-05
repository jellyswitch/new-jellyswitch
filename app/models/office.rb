# == Schema Information
#
# Table name: offices
#
#  id             :bigint(8)        not null, primary key
#  capacity       :integer          default(1), not null
#  description    :text
#  name           :string
#  slug           :string
#  square_footage :integer          default(0), not null
#  visible        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  location_id    :bigint(8)
#  operator_id    :bigint(8)        not null
#
# Indexes
#
#  index_offices_on_location_id  (location_id)
#  index_offices_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (operator_id => operators.id)
#

class Office < ApplicationRecord
  belongs_to :operator

  has_many :office_leases
  belongs_to :location

  acts_as_scopable :operator, :location
  has_one_attached :lease
  has_one_attached :photo

  extend FriendlyId
  friendly_id :name, use: :slugged

  scope :visible, -> { where(visible: true) }

  def self.available_for_lease
    offices = visible.left_outer_joins(:office_leases)

    offices.
      where(office_leases: { office: nil }).
      or(offices.where('office_leases.end_date <= ?', Time.current))
  end

  def has_active_lease?
    active_leases.count > 0
  end

  def active_leases
    office_leases.active
  end

  def has_photo?
    photo.attached?
  end

  def square_photo
    photo.variant(combine_options: {auto_orient: true, resize: "300x300"})
  end

  def card_photo
    photo.variant(combine_options: {auto_orient: true, resize: "x200"})
  end
end
