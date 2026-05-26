
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
  dollars :hourly_rate, :credit_cost, :childcare_reservation_cost

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
  has_many :product_email_templates
  has_many :lease_renewal_requests
  has_many :tracking_pixels
  accepts_nested_attributes_for :tracking_pixels, allow_destroy: true, reject_if: ->(attributes) { attributes['name'].blank? || attributes['script'].blank? }

  has_many :location_managements
  has_many :managers, through: :location_managements, source: :user

  has_one_attached :background_image
  has_one_attached :photo

  has_many :user_payment_profiles, dependent: :destroy

  normalizes :kisi_api_key, with: ->(v) { v.blank? ? nil : v }

  # CRM is always on for every location. See Operator#crm_enabled? — the DB
  # column is kept for history but the predicate short-circuits to true.
  def crm_enabled?
    true
  end

  after_create_commit :seed_email_templates

  validates :working_day_start, presence: true
  validates :working_day_end, presence: true
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

  private

  def seed_email_templates
    ProductEmailTemplate.seed_defaults_for(operator, location: self)
  end

  class StripeOperator < SimpleDelegator
    include StripeUtils
  end

  private_constant :StripeOperator
end
