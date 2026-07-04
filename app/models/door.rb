# == Schema Information
#
# Table name: doors
#
#  id          :bigint(8)        not null, primary key
#  available   :boolean          default(TRUE), not null
#  name        :string           not null
#  private     :boolean
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  kisi_id     :integer
#  location_id :bigint(8)
#  operator_id :integer          default(1), not null
#
# Indexes
#
#  index_doors_on_location_id  (location_id)
#  index_doors_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#

class Door < ApplicationRecord
  searchkick
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Relationships
  has_many :door_punches, dependent: :destroy
  belongs_to :operator
  belongs_to :location
  # ADR 0021: attached to a Room ⇒ this door is that Room's LOCK —
  # reservation-gated, not coverage-gated. nil ⇒ Building Door.
  belongs_to :room, optional: true
  acts_as_scopable :operator, :location

  # Scopes
  scope :available, -> { where(available: true) }
  scope :unavailable, -> { where(available: false) }

  def room_lock?
    room_id.present?
  end

  ROOM_LOCK_EARLY_GRACE = 10.minutes

  # ADR 0021: a Room Lock opens for staff anytime, or the reservation
  # holder during their booking — including up to ROOM_LOCK_EARLY_GRACE
  # early, but only when no other booking still occupies the room (early
  # building entry is hospitality; early ROOM entry collides with the
  # previous meeting).
  #
  # This is the single home for the rule: every unlock surface (api/v1
  # DoorUnlocking, the operator web open action, the legacy /api unlock)
  # authorizes through it.
  def openable_as_room_lock_by?(user)
    return false if user.nil? || room.nil?
    return true if user.superadmin?
    return true if location && user.admin_or_manager?(location)

    # Reservation's default_scope already excludes cancelled bookings.
    now = Time.current
    holder_res = room.reservations
      .where(user: user)
      .overlapping(now, now + ROOM_LOCK_EARLY_GRACE)
      .order(:datetime_in)
      .first
    return false unless holder_res

    # Booking hasn't started yet (we're inside the grace window): the room
    # must actually be free — a still-running prior booking wins.
    if holder_res.datetime_in > now
      occupied = room.reservations
        .where.not(id: holder_res.id)
        .overlapping(now, now)
        .exists?
      return !occupied
    end

    true
  end

  def search_data
    {
      name: name,
      operator_id: operator_id,
    }
  end
end
