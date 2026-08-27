
# == Schema Information
#
# Table name: locations
#
#  id                                  :bigint(8)        not null, primary key
#  allow_hourly                        :boolean          default(FALSE), not null
#  announcements_enabled               :boolean          default(TRUE), not null
#  billing_state                       :string
#  building_access_instructions        :string
#  building_address                    :string
#  bulletin_board_enabled              :boolean          default(FALSE), not null
#  childcare_enabled                   :boolean          default(TRUE), not null
#  childcare_reservation_cost_in_cents :integer          default(0), not null
#  city                                :string
#  common_square_footage               :integer          default(0), not null
#  contact_email                       :string
#  contact_name                        :string
#  contact_phone                       :string
#  credit_cost_in_cents                :integer          default(0), not null
#  credits_enabled                     :boolean          default(FALSE), not null
#  crm_enabled                         :boolean          default(TRUE), not null
#  door_integration_enabled            :boolean          default(TRUE), not null
#  events_enabled                      :boolean          default(TRUE), not null
#  flex_square_footage                 :integer          default(0), not null
#  google_reviews_url                  :string
#  hourly_rate_in_cents                :integer          default(0), not null
#  kisi_api_key                        :string
#  latitude                            :decimal(10, 7)
#  longitude                           :decimal(10, 7)
#  name                                :string
#  new_users_get_free_day_pass         :boolean          default(FALSE), not null
#  offices_enabled                     :boolean          default(FALSE), not null
#  open_friday                         :boolean          default(TRUE), not null
#  open_monday                         :boolean          default(TRUE), not null
#  open_saturday                       :boolean          default(FALSE), not null
#  open_sunday                         :boolean          default(FALSE), not null
#  open_thursday                       :boolean          default(TRUE), not null
#  open_tuesday                        :boolean          default(TRUE), not null
#  open_wednesday                      :boolean          default(TRUE), not null
#  overage_rate_in_cents               :integer          default(0), not null
#  past_member_grace_days              :integer          default(180), not null
#  renewal_reminder_days               :integer
#  rooms_enabled                       :boolean          default(TRUE), not null
#  sender_email                        :string
#  snippet                             :string
#  square_footage                      :integer
#  state                               :string
#  stripe_access_token                 :string
#  stripe_publishable_key              :string
#  stripe_refresh_token                :string
#  time_zone                           :string           default("Pacific Time (US & Canada)"), not null
#  visible                             :boolean          default(TRUE), not null
#  wifi_name                           :string
#  wifi_password                       :string
#  working_day_end                     :string           default("18:00"), not null
#  working_day_start                   :string           default("09:00"), not null
#  zip                                 :string
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  operator_id                         :bigint(8)
#  space_host_id                       :bigint(8)
#  stripe_user_id                      :string
#
# Indexes
#
#  index_locations_on_operator_id     (operator_id)
#  index_locations_on_space_host_id   (space_host_id)
#  index_locations_on_state_and_city  (state,city)
#  index_locations_on_zip             (zip)
#

class Location < ApplicationRecord
  searchkick
  belongs_to :operator
  acts_as_tenant :operator

  # Optional override for who appears as the auto-greeting chat host at this
  # location. When nil, `LandingHelper#space_host_for` falls back to the
  # role-based algorithm (GM at this location → oldest operator admin).
  # See migration 20260526040628_add_space_host_to_locations for why this
  # isn't a Postgres FK (cross-tenant assignment is enforced at the app
  # layer, not the schema).
  belongs_to :space_host, class_name: "User", optional: true

  include HasDollars
  # overage_rate = the "Overage / add-on meeting room time" rate (ADR 0012).
  # Charged per minute for $0 (call) rooms beyond any day-pass allowance, and
  # for any booker of a $0 room with no day-pass coverage. See ChargeCalculator.
  dollars :hourly_rate, :credit_cost, :childcare_reservation_cost, :overage_rate

  geocoded_by :address_string
  after_validation :geocode, if: -> { address_changed? && building_address.present? }

  has_many :checkins
  has_many :childcare_slots
  has_many :childcare_reservations, through: :childcare_slots
  has_many :doors
  has_many :beacons
  has_many :events
  has_many :rooms
  has_many :offices
  has_many :office_leases
  has_many :posts
  has_many :feed_items
  has_many :member_feedbacks
  has_many :announcements
  has_many :day_passes
  has_many :day_pass_types
  has_many :organizations
  has_many :weekly_updates
  has_many :plans
  has_many :plan_categories
  has_many :invoices
  has_many :users, class_name: "User", foreign_key: "original_location_id"
  has_many :current_users, class_name: "User", foreign_key: "current_location_id"
  has_many :product_email_templates, dependent: :destroy
  has_many :lease_renewal_requests
  has_many :tracking_pixels
  accepts_nested_attributes_for :tracking_pixels, allow_destroy: true, reject_if: ->(attributes) { attributes['name'].blank? || attributes['script'].blank? }

  has_many :location_managements
  has_many :managers, through: :location_managements, source: :user

  has_one_attached :background_image
  has_one_attached :photo

  has_many :user_payment_profiles, dependent: :destroy

  normalizes :kisi_api_key, with: ->(v) { v.blank? ? nil : v }

  # Working-hours times are consumed verbatim by the `working_hours` gem, which
  # only accepts zero-padded 24h "HH:MM". A value like "5:00" (easy to type into
  # the free-text Settings > Hours field) raised WorkingHours::InvalidConfiguration
  # and 500'd the operator dashboard. Normalize on assignment so common typos
  # self-heal ("5:00" -> "05:00", "5" -> "05:00", seconds dropped); the format
  # validation below rejects anything still malformed.
  WORKING_TIME_FORMAT = /\A(?:[01]\d|2[0-3]):[0-5]\d\z|\A24:00\z/

  def self.normalize_working_time(value)
    return value if value.blank?

    s = value.to_s.strip
    if (m = s.match(/\A(\d{1,2}):(\d{2})(?::\d{2})?\z/))
      format("%02d:%02d", m[1].to_i, m[2].to_i)
    elsif s.match?(/\A\d{1,2}\z/)
      format("%02d:00", s.to_i)
    else
      s
    end
  end

  normalizes :working_day_start, with: ->(v) { Location.normalize_working_time(v) }
  normalizes :working_day_end, with: ->(v) { Location.normalize_working_time(v) }

  # `normalizes` only runs on cast (assignment/write), NOT on read — so a row
  # written before it shipped (Tahoe Longhouse onboarded 2026-06-11, one day
  # before the normalizer) loads its raw "5:00" and then fails the format
  # validation on EVERY save. That silently blocks UNRELATED settings forms
  # (the WiFi & Pixels save runs full Location validation). Re-normalize before
  # validation so such legacy/bypass values self-heal; genuinely invalid input
  # (e.g. "9am") still normalizes to itself and is correctly rejected.
  before_validation :renormalize_working_times

  # CRM is always on for every location. See Operator#crm_enabled? — the DB
  # column is kept for history but the predicate short-circuits to true.
  def crm_enabled?
    true
  end

  # True when `at` falls within this location's posted business hours — the
  # basis for the "business_hours" membership building-access tier. Evaluated
  # in the location's own timezone; handles overnight windows (end <= start);
  # a blank/unparseable working time is treated as closed rather than raising.
  def open_at?(at = Time.current)
    zone = ActiveSupport::TimeZone[time_zone.presence || "UTC"] || ActiveSupport::TimeZone["UTC"]
    local = at.in_time_zone(zone)
    return false unless open_on?(local.to_date)

    within_posted_hours?(at)
  end

  # Time-of-day check ONLY — whether `at` falls inside working_day_start..
  # working_day_end in the location's zone, ignoring the open_<day> flags.
  # Day-pass door access and member self-serve booking bounds use THIS rather
  # than open_at?: the open-day flags describe STAFFED days, and weekend
  # day-pass usage is established, accepted behavior (prod audit 2026-08-07:
  # ~20 weekend daytime day-pass entries/month at Cowork Tahoe alone would
  # have been blocked by a day-flag gate). Handles overnight windows
  # (end <= start); blank/unparseable working times read as closed.
  def within_posted_hours?(at = Time.current)
    zone = ActiveSupport::TimeZone[time_zone.presence || "UTC"] || ActiveSupport::TimeZone["UTC"]
    local = at.in_time_zone(zone)

    to_min = ->(hhmm) { (m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})\z/)) ? m[1].to_i * 60 + m[2].to_i : nil }
    start_min = to_min.call(working_day_start)
    end_min   = to_min.call(working_day_end)
    return false if start_min.nil? || end_min.nil?

    now_min = local.hour * 60 + local.min
    if end_min > start_min
      now_min >= start_min && now_min < end_min
    elsif end_min < start_min
      now_min >= start_min || now_min < end_min # overnight window (e.g. 22:00–05:00)
    else
      false # zero-length window
    end
  end

  # The concrete [open, close) instants of `date`'s posted hours in this
  # location's zone — the span a Day Office hold occupies (ADR 0026). Returns
  # nil when the working time is blank/unparseable or the window is overnight
  # or zero-length (a day-office hold needs a same-date daytime span; overnight
  # posted hours are not supported for office holds). Wall-clock construction
  # keeps 08:00 meaning 08:00 across DST transitions.
  #
  # A validated working_day_end of "24:00" rolls to midnight at the START of
  # the next day (span.last.to_date == date + 1) — deliberate close-of-day
  # semantics, not a bug. Callers deriving a duration should compute
  # ((span.last - span.first) / 60).round: subtraction yields Float seconds,
  # and .round guards the DST-straddling case where real elapsed minutes
  # differ from the naive HH:MM difference.
  def posted_hours_span(date)
    zone = ActiveSupport::TimeZone[time_zone.presence || "UTC"] || ActiveSupport::TimeZone["UTC"]
    to_min = ->(hhmm) { (m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})\z/)) ? m[1].to_i * 60 + m[2].to_i : nil }
    start_min = to_min.call(working_day_start)
    end_min   = to_min.call(working_day_end)
    return nil if start_min.nil? || end_min.nil? || end_min <= start_min

    [zone.local(date.year, date.month, date.day, start_min / 60, start_min % 60),
     zone.local(date.year, date.month, date.day, end_min / 60, end_min % 60)]
  end

  # Whether the location is open at all on `date`'s weekday (open_<day> flags).
  # The date is taken as already location-local — callers pass a member-facing
  # calendar date, not an instant.
  def open_on?(date)
    [open_sunday, open_monday, open_tuesday, open_wednesday,
     open_thursday, open_friday, open_saturday][date.wday]
  end

  # Member-facing "6:00 AM – 8:00 PM" label for error messages and closed
  # states. Falls back to the raw stored string if one side doesn't parse.
  def posted_hours_label
    fmt = ->(hhmm) {
      m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
      m ? Time.utc(2000, 1, 1, m[1].to_i, m[2].to_i).strftime("%-l:%M %p") : hhmm.to_s
    }
    "#{fmt.call(working_day_start)} – #{fmt.call(working_day_end)}"
  end

  # Editable data list — states where expiration on prepaid passes is restricted
  # or prohibited. Add states here as counsel advises; this is data, not logic.
  EXPIRATION_RESTRICTED_STATES = ["CA", "CALIFORNIA"].freeze

  # Fail-safe: unknown/blank state is treated as restricted (no expiration).
  def expiration_restricted?
    norm = state.to_s.strip.upcase
    return true if norm.blank?
    EXPIRATION_RESTRICTED_STATES.include?(norm)
  end

  after_create_commit :seed_email_templates

  validates :working_day_start, presence: true
  validates :working_day_end, presence: true
  validates :working_day_start, format: { with: WORKING_TIME_FORMAT }, allow_blank: true
  validates :working_day_end, format: { with: WORKING_TIME_FORMAT }, allow_blank: true
  validates :past_member_grace_days,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 120, less_than_or_equal_to: 365 }
  validate :space_host_belongs_to_same_operator

  def space_host_belongs_to_same_operator
    return if space_host_id.blank?
    return if space_host && space_host.operator_id == operator_id

    errors.add(:space_host_id, "must be a member of this operator")
  end

  scope :visible, -> { where(visible: true) }

  delegate :create_stripe_customer,
           :retrieve_stripe_customer,
           :create_stripe_invoice_item,
           :create_stripe_invoice,
           :retrieve_stripe_invoice,
           :create_stripe_refund,
           :retrieve_stripe_refund,
           :create_stripe_subscription,
           :retrieve_stripe_plans,
           :create_stripe_plan,
           :update_stripe_subscription_price,
           :mark_invoice_paid,
           :create_or_update_customer_payment,
           :charge_invoice,
           :retrieve_stripe_customers,
           :list_stripe_subscriptions,
           :update_organization_customer_details,
           :stripe_request,
           to: :stripe_operator

  def search_data
    {
      name: name,
      text: snippet,
      operator_id: operator_id,
    }
  end

  def has_photo?
    background_image.attached?
  end

  def has_categories?
    plan_categories.select do |plan_category|
      plan_category.plans.individual.available.visible.for_location(self).count.positive?
    end.count.positive?
  end

  def square_photo
    background_image.variant(resize: "100x100>")
  end

  def has_contact_info?
    contact_name.present? && contact_email.present? && contact_phone.present?
  end

  # Predicates for high-level features

  def hourly_enabled?
    allow_hourly?
  end

  def rentable_rooms_enabled?
    rooms.visible.rentable.count > 0
  end

  def full_address
    "#{building_address}, #{city} #{state} #{zip}"
  end

  def stripe_secret_key
    if operator.production? && operator.subdomain != "southlakecoworking"
      Rails.configuration.stripe[:secret_key]
    else
      Rails.configuration.stripe[:test_secret_key]
    end
  end

  # Overrides the DB column: Stripe Connect OAuth stores the connected
  # account's live-mode key there, so a prod snapshot copied to staging would
  # serve pk_live against test-mode secret keys. Serve the platform key from
  # env config, mode-matched to stripe_secret_key; clients pass stripe_user_id
  # as the Stripe-Account header, so tokens still mint on the connected account.
  def stripe_publishable_key
    if operator.production? && operator.subdomain != "southlakecoworking"
      Rails.configuration.stripe[:publishable_key]
    else
      Rails.configuration.stripe[:test_publishable_key]
    end
  end

  def stripe_operator
    @stripe_operator ||= StripeOperator.new(self)
  end

  def day_passes_enabled?
    day_pass_types.count > 0
  end

  def memberships_enabled?
    plans.individual.visible.available.count > 0
  end

  def onboarded?
    plans.count > 0 &&
    day_pass_types.count > 0 &&
    users.members.count > 0
  end

  def stripe_setup?
    stripe_user_id.present?
  end

  def has_active_office_leases?
    office_leases.active.count > 0
  end

  # Email settings — location overrides operator defaults

  def sender_from_address
    if sender_email.present?
      "#{name} <#{sender_email}>"
    else
      operator.sender_from_address
    end
  end

  def effective_google_reviews_url
    url = google_reviews_url.presence || operator.google_reviews_url
    return nil unless url.present?
    url.start_with?("http") ? url : "https://#{url}"
  end

  def effective_renewal_reminder_days
    renewal_reminder_days || operator.renewal_reminder_days
  end

  def address_string
    [building_address, city, state, zip].compact_blank.join(", ")
  end

  def address_changed?
    building_address_changed? || city_changed? || state_changed? || zip_changed?
  end

  # The [start, end) timestamps of the business-day period containing `at`,
  # using day_pass_period_start as the rollover in this location's time zone.
  # An entry any time within one window counts as the same "day" for bundle
  # burning, so an evening session crossing midnight burns one pass.
  def business_day_window(at = Time.current)
    tz = ActiveSupport::TimeZone[time_zone.presence || "UTC"]
    local = at.in_time_zone(tz)
    h, m = (day_pass_period_start.presence || "04:00").split(":").map(&:to_i)
    # Guard against a malformed value (e.g. "9am") that yields only one token;
    # m will be nil in that case. Fall back to the 04:00 default so the burn
    # path never raises.
    h, m = 4, 0 if m.nil?
    period_start_str = format("%02d:%02d", h, m)
    offset = (h * 3600) + (m * 60)
    day = (local - offset).to_date
    start = tz.parse("#{day} #{period_start_str}")
    [start, start + 1.day]
  end

  # Per-location Concierge offer/promo, falling back to the operator-level
  # text so single-location brands keep configuring one field.
  def concierge_offer
    concierge_offer_text.presence || operator.concierge_offer_text
  end

  private

  def renormalize_working_times
    self.working_day_start = self.class.normalize_working_time(working_day_start)
    self.working_day_end = self.class.normalize_working_time(working_day_end)
  end

  def seed_email_templates
    ProductEmailTemplate.seed_defaults_for(operator, location: self)
  end

  class StripeOperator < SimpleDelegator
    include StripeUtils
  end

  private_constant :StripeOperator
end
