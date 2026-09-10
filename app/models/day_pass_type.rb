# == Schema Information
#
# Table name: day_pass_types
#
#  id                            :bigint(8)        not null, primary key
#  always_allow_building_access  :boolean          default(FALSE), not null
#  amount_in_cents               :integer          default(0), not null
#  available                     :boolean          default(TRUE), not null
#  code                          :string
#  daily_limit                   :integer
#  default_for_room_booking      :boolean          default(FALSE), not null
#  expires_after_days            :integer
#  included_meeting_room_minutes :integer
#  kind                          :string           default("standard"), not null
#  name                          :string           not null
#  overage_rate_in_cents         :integer          default(0), not null
#  quantity                      :integer          default(1), not null
#  visible                       :boolean          default(TRUE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :integer
#  operator_id                   :integer          not null
#
# Indexes
#
#  index_day_pass_types_on_location_id  (location_id)
#  index_dpt_on_op_loc_default          (operator_id,location_id,default_for_room_booking)
#

class DayPassType < ApplicationRecord
  include HasLocation

  has_many :day_passes
  has_many :day_pass_type_rooms, -> { order(:position, :id) }, dependent: :destroy
  has_many :office_rooms, through: :day_pass_type_rooms, source: :room

  # String-backed kind: the first *behavioral* distinction between types.
  # Never infer office behavior from the name (retired %office% ILIKE).
  # validate: true trades the setter's raise-on-assignment (ArgumentError,
  # an uncatchable 500) for a normal inclusion validation error (422).
  enum :kind, { standard: "standard", day_office: "day_office" }, default: :standard, validate: true

  validates :location, presence: { message: "is required for Day Office types" }, if: :day_office?

  belongs_to :operator
  acts_as_tenant :operator

  has_rich_text :description

  # Scopes
  scope :available, -> { where(available: true) }
  scope :unavailable, -> { where(available: false) }
  scope :visible, -> { where(visible: true) }
  scope :invisible, -> { where(visible: false) }
  scope :free, -> { where(amount_in_cents: 0) }
  scope :for_operator, ->(operator) { where(operator_id: operator.id) }
  # Case-insensitive + whitespace-tolerant lookup. Matches DiscountCode#for_code.
  # Shelley reported a real-world failure where her discount code didn't work
  # because exact-match case-sensitive comparison rejected anything other than
  # the stored capitalization.
  scope :for_code, ->(code) { where("LOWER(code) = ?", code.to_s.downcase.strip) }
  scope :cheapest, -> { order("amount_in_cents ASC").first }

  def self.options_for_select(operator)
    where(operator_id: operator.id).available.visible
  end

  def self.all_options_for_select(location, user)
    if user.has_billing_for_location?(location) || user.out_of_band?
      where(location_id: location.id).available
    else
      where(location_id: location.id).available.free
    end
  end

  # The regular pass to offer when an office is sold out — same preference
  # order CoverageState uses for coverage auto-buy suggestions (ADR 0026). A
  # location-specific default_for_room_booking type beats an operator-wide
  # (nil-location) one; both orderings tiebreak on id for a deterministic pick.
  # quantity: 1 excludes N-Packs — a bundle id posted back to a purchase
  # endpoint routes into the dateless bundle-buy flow, not a same-day swap.
  def self.suggested_standard_for(location)
    return nil if location.nil?
    scope = where(operator_id: location.operator_id)
              .for_location(location)
              .available.where(visible: true).where("amount_in_cents > 0")
              .where.not(kind: "day_office")
              .where(quantity: 1)
    scope.where(default_for_room_booking: true).order(Arel.sql("location_id DESC NULLS LAST"), :id).first ||
      scope.order(:amount_in_cents, :id).first
  end

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :daily_limit, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
                          allow_nil: true

  # Presented wherever expiration can be enabled. NOT legal advice.
  EXPIRATION_DISCLAIMER =
    "Expiration on prepaid passes is restricted or prohibited in many states, " \
    "including California (Civil Code §1749.5). It can't be enabled for this location.".freeze

  validate :expiration_allowed_for_location
  validate :pack_name_matches_quantity

  # A SKU named like an N-pack must mint N passes. Guards the fake-bundle
  # mis-sell shipped twice (TLH 2026-08-10, Untethered Fulton 2026-08-27):
  # "2 day pass pack" with quantity 1 sells two-pack money for one pass.
  # The pattern was audited against every production SKU — zero false
  # positives; a name it doesn't match is simply not guarded.
  def pack_name_matches_quantity
    match = name.to_s.match(/(\d+)[\s-]*(day\s*)?(pass\s*)?(es)?\s*pack/i)
    return unless match

    expected = match[1].to_i
    return if expected.zero? || quantity == expected

    errors.add(:quantity, "is #{quantity}, but the name says #{expected}-pack — a buyer would pay for #{expected} passes and receive #{quantity}")
  end

  def expiration_allowed_for_location
    return if expires_after_days.blank?
    if location.nil? || location.expiration_restricted?
      errors.add(:expires_after_days, EXPIRATION_DISCLAIMER)
    end
  end

  # A quantity > 1 product is an N-Pack (a Day Pass Bundle); quantity 1 is a
  # single day pass. See CONTEXT.md → Day Pass Bundle.
  def bundle?
    quantity.to_i > 1
  end

  # Daily sales cap. Every DayPass row of this type on that day at that
  # location counts — purchased, comped, or bundle-sourced — because the limit
  # models physical capacity (e.g. the building has 2 day offices), not sales
  # volume. Enforced only at member self-serve entry points; staff/admin and
  # door-entry paths never call this (their rows still count).
  #
  # For day_office types the pool IS the capacity: sold out = no pool room
  # free that day; the stored daily_limit is ignored (ADR 0026, decision #7).
  def daily_limit_reached?(day:, location:)
    if day_office?
      return DayOffices::Allocator.available_room(day_pass_type: self, day: day).nil?
    end
    return false if daily_limit.nil?
    day_passes.where(location: location, day: day).count >= daily_limit
  end

  def free?
    amount_in_cents == 0
  end

  # A Day Office type whose pool has no active rooms can never allocate. From
  # the allocator's side "no room free today" and "no rooms at all" look the
  # same (nil), so this is what lets a caller say the honest thing: it's a
  # configuration gap, not demand. Mirrors the allocator's Room.active filter.
  def office_pool_empty?
    day_office? && office_rooms.merge(Room.active).none?
  end

  # nil when the pool can hold a pass; otherwise one staff-actionable sentence.
  # Two ways a pool is unusable: no active rooms at all, or a room whose
  # capacity is 0 (the hold is a 1-attendee reservation, which the room's
  # capacity validation rejects — TLH's "Meeting Room" shipped with 0 and the
  # operator saw "Attendee count can't exceed the room's capacity of 0").
  def office_pool_problem
    return nil unless day_office?

    rooms = office_rooms.merge(Room.active).to_a
    if rooms.empty?
      return "#{name} can't be booked yet: no rooms are in its Day Office pool. Add rooms to it under Day Pass Types."
    end

    zero = rooms.select { |r| r.capacity.to_i < 1 }
    return nil if zero.empty?

    "#{name} can't be booked yet: #{zero.map(&:name).to_sentence} #{zero.one? ? 'has' : 'have'} " \
    "a capacity of 0. Set the capacity under Rooms."
  end

  # The one place a sold-out / can't-book message is worded, so every surface
  # (API, web member checkout, admin add, reschedule, concierge, allocation)
  # says the same thing. `date_text` lets the web flow keep its short_date
  # idiom. An empty pool is called out as such instead of "fully booked" —
  # TLH's "Private Office Day Pass +1" said fully booked on every date for a
  # week because nobody had put rooms in its pool.
  def sold_out_message(day, date_text: day.strftime("%B %e"))
    office_pool_problem || "#{name.pluralize} are fully booked for #{date_text}. Try another day."
  end

  # Full-list semantics, mirroring Room#reassign_doors!: `positions` is
  # {room_id => position}; rooms absent from the hash leave the pool. Blank
  # keys (a form's hidden "clear all" input, mirroring reassign_doors!) are
  # dropped rather than treated as a real room id.
  #
  # The resets MUST run in `ensure`, not just after the transaction: on a
  # validation failure (e.g. a cross-location room), find_or_initialize_by
  # has already pushed the new, invalid, unsaved record into the
  # association's in-memory target — that happens in Ruby, not the DB, so
  # the transaction rollback can't undo it. Left in place, that phantom
  # record gets re-validated by the has_many autosave-validation callback on
  # every later save of this DayPassType, failing it with "Day pass type
  # rooms is invalid" — for a save that has nothing to do with the pool.
  def assign_office_rooms!(positions)
    positions = positions.reject { |room_id, _| room_id.blank? }
    transaction do
      day_pass_type_rooms.where.not(room_id: positions.keys).destroy_all
      positions.each do |room_id, position|
        day_pass_type_rooms.find_or_initialize_by(room_id: room_id)
                           .update!(position: position)
      end
    end
  ensure
    day_pass_type_rooms.reset
    office_rooms.reset
  end

  # Meeting room limit helpers
  def has_meeting_room_limit?
    included_meeting_room_minutes.present?
  end

  def overage_rate_per_minute_in_cents
    overage_rate_in_cents / 60.0
  end
end
