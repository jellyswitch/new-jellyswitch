
# == Schema Information
#
# Table name: locations
#
#  id                                  :bigint(8)        not null, primary key
#  allow_hourly                        :boolean          default(FALSE), not null
#  billing_state                       :string
#  building_access_instructions        :string
#  building_address                    :string
#  childcare_reservation_cost_in_cents :integer          default(0), not null
#  city                                :string
#  common_square_footage               :integer          default(0), not null
#  contact_email                       :string
#  contact_name                        :string
#  contact_phone                       :string
#  credit_cost_in_cents                :integer          default(0), not null
#  flex_square_footage                 :integer          default(0), not null
#  hourly_rate_in_cents                :integer          default(0), not null
#  name                                :string
#  new_users_get_free_day_pass         :boolean          default(FALSE), not null
#  open_friday                         :boolean          default(TRUE), not null
#  open_monday                         :boolean          default(TRUE), not null
#  open_saturday                       :boolean          default(FALSE), not null
#  open_sunday                         :boolean          default(FALSE), not null
#  open_thursday                       :boolean          default(TRUE), not null
#  open_tuesday                        :boolean          default(TRUE), not null
#  open_wednesday                      :boolean          default(TRUE), not null
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
#  stripe_user_id                      :string
#  kisi_api_key                        :string
#  skip_onboarding                     :boolean          default(FALSE), not null
#  announcements_enabled               :boolean
#  events_enabled                      :boolean
#  door_integration_enabled            :boolean
#  rooms_enabled                       :boolean
#  offices_enabled                     :boolean
#  bulletin_board_enabled              :boolean
#  credits_enabled                     :boolean
#  childcare_enabled                   :boolean
#  crm_enabled                         :boolean
#
# Indexes
#
#  index_locations_on_operator_id     (operator_id)
#  index_locations_on_state_and_city  (state,city)
#  index_locations_on_zip             (zip)
#

class Location < ApplicationRecord
  searchkick
  belongs_to :operator
  acts_as_tenant :operator

  has_many :checkins
  has_many :childcare_slots
  has_many :childcare_reservations, through: :childcare_slots
  has_many :doors
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

  has_one_attached :background_image
  has_one_attached :photo

  validates :working_day_start, presence: true
  validates :working_day_end, presence: true

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
      text: snippet
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

  private

  class StripeOperator < SimpleDelegator
    include StripeUtils
  end

  private_constant :StripeOperator
end
