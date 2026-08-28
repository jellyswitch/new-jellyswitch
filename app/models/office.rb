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
#  operator_id    :bigint(8)
#
# Indexes
#
#  index_offices_on_location_id  (location_id)
#  index_offices_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id) ON DELETE => nullify
#

class Office < ApplicationRecord
  belongs_to :operator

  has_many :office_leases, dependent: :destroy
  belongs_to :location

  acts_as_scopable :operator, :location
  has_one_attached :lease
  has_one_attached :photo

  extend FriendlyId
  friendly_id :name, use: :slugged

  # Guard against accidental duplicate offices (e.g. double form submission).
  # Scoped to the visible set so a name can be reused after archiving.
  validates :name, presence: true
  validates :name, uniqueness: {
    scope: :location_id,
    case_sensitive: false,
    conditions: -> { where(visible: true) },
  }, if: :visible?

  scope :visible, -> { where(visible: true) }
  scope :archived, -> { where(visible: false) }

  def self.available_for_lease
    offices = visible.left_outer_joins(:office_leases)

    offices.
      where(office_leases: { office: nil }).
      or(offices.where("office_leases.end_date <= ?", Time.current)).
      distinct().
      order(:name).
      select { |o| o.available? }
  end

  def self.upcoming_renewals(num_days = OfficeLease::RENEWAL_WINDOW_DAYS)
    offices = visible.left_outer_joins(:office_leases)

    # `.distinct` collapses duplicate office rows produced by the join; ordering
    # happens in Ruby because Postgres forbids SELECT DISTINCT ordered by a
    # joined column that isn't in the select list.
    offices.
      where("office_leases.end_date >= ? AND office_leases.end_date < ?", Time.current, Time.current + num_days.days).
      distinct.
      select { |o| o.active_lease.present? }.
      sort_by { |o| o.active_lease.end_date }
  end

  def self.occupied
    visible.select { |office| office.has_active_lease? }
  end

  def has_active_lease?
    active_leases.count > 0
  end

  def available?
    !has_active_lease?
  end

  def active_leases
    office_leases.active
  end

  def active_lease
    office_leases.active.first
  end

  def has_photo?
    photo.attached?
  end

  def square_photo
    photo.variant(auto_orient: true, resize: "300x300")
  end

  def card_photo
    photo.variant(auto_orient: true, resize: "x200")
  end

  def thumbnail
    photo.variant(resize: "180x180", auto_orient: true)
  end
  # Office Inventory listing rule (2026-08-27 plan §8):
  #   :now  — visible and no active lease (auto-listed)
  #   Date  — leased, but staff flipped coming_available: the current lease's
  #           end date ("Available from <date>"); NEVER derived automatically —
  #           a tenant might renew, and their departure is not public until
  #           staff say so.
  #   nil   — not listed.
  def listed_availability
    return nil unless visible?

    lease = office_leases.active.order(end_date: :desc).first
    return :now if lease.nil?
    return lease.end_date if coming_available?

    nil
  end

end
