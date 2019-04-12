# == Schema Information
#
# Table name: offices
#
#  id          :bigint(8)        not null, primary key
#  capacity    :integer          default(1), not null
#  description :text
#  name        :string
#  slug        :string
#  visible     :boolean          default(TRUE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :bigint(8)        not null
#
# Indexes
#
#  index_offices_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => operators.id)
#

class Office < ApplicationRecord
  belongs_to :operator
  acts_as_tenant :operator

  has_many :office_leases

  has_one_attached :lease
  has_one_attached :photo

  extend FriendlyId
  friendly_id :name, use: :slugged

  scope :visible, -> { where(visible: true) }

  def self.available_for_lease
    offices = visible.left_outer_joins(:office_leases)

    offices.
      where(office_leases: { office: nil }).
      or(offices.where('office_leases.end_date < ?', Time.current))
  end

  def has_lease?
    lease.attached?
  end

  def has_photo?
    photo.attached?
  end

  def square_photo
    photo.variant(resize: "300x300")
  end

  def card_photo
    photo.variant(resize: "x200")
  end
end
