# == Schema Information
#
# Table name: operators
#
#  id                                  :bigint(8)        not null, primary key
#  android_server_key                  :string
#  android_url                         :string
#  announcements_enabled               :boolean          default(TRUE), not null
#  approval_required                   :boolean          default(TRUE), not null
#  billing_state                       :string           default("demo"), not null
#  building_address                    :string           default("not set"), not null
#  bulletin_board_enabled              :boolean          default(FALSE), not null
#  cancellation_window_hours           :integer          default(24), not null
#  checkin_notifications               :boolean          default(TRUE), not null
#  checkin_required                    :boolean          default(FALSE), not null
#  childcare_enabled                   :boolean          default(FALSE), not null
#  contact_email                       :string
#  contact_name                        :string
#  contact_phone                       :string
#  credits_enabled                     :boolean          default(FALSE), not null
#  crm_enabled                         :boolean          default(FALSE), not null
#  day_pass_cost_in_cents              :integer          default(2500), not null
#  day_pass_notifications              :boolean          default(TRUE), not null
#  door_integration_enabled            :boolean          default(TRUE), not null
#  email_enabled                       :boolean          default(FALSE), not null
#  events_enabled                      :boolean          default(TRUE), not null
#  google_reviews_url                  :string
#  ios_url                             :string
#  kisi_api_key                        :string
#  last_activities_backfilled_at       :datetime
#  mailchimp_api_key                   :string
#  member_feedback_notifications       :boolean          default(TRUE), not null
#  membership_notifications            :boolean          default(TRUE), not null
#  membership_text                     :string
#  name                                :string           not null
#  offices_enabled                     :boolean          default(TRUE), not null
#  paid_room_reservation_notifications :boolean          default(TRUE), not null
#  post_notifications                  :boolean          default(TRUE), not null
#  refund_fee_percent                  :integer          default(0), not null
#  refund_notifications                :boolean          default(TRUE), not null
#  renewal_reminder_days               :integer          default(7)
#  reservation_notifications           :boolean          default(FALSE), not null
#  rooms_enabled                       :boolean          default(TRUE), not null
#  sender_email                        :string
#  signup_notifications                :boolean          default(FALSE), not null
#  skip_onboarding                     :boolean          default(FALSE), not null
#  snippet                             :string           default("Generic snippet about the space"), not null
#  square_footage                      :integer          default(0), not null
#  stripe_access_token                 :string
#  stripe_publishable_key              :string
#  stripe_refresh_token                :string
#  subdomain                           :string           not null
#  tour_widget_enabled                 :boolean          default(FALSE), not null
#  tour_widget_thank_you_url           :string
#  wifi_name                           :string           default("not set"), not null
#  wifi_password                       :string           default("not set"), not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  bundle_id                           :string
#  firebase_project_id                 :string
#  mailchimp_audience_id               :string
#  stripe_user_id                      :string
#
# Indexes
#
#  index_operators_on_subdomain  (subdomain) UNIQUE
#

class Operator < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged, slug_column: :subdomain

  include HasDollars
  dollars :day_pass_cost

  # CRM is always on for every operator. The DB column is kept for history but
  # ignored by the predicate so existing checks like operator.crm_enabled? short-
  # circuit to true regardless of stored value.
  def crm_enabled?
    true
  end

  validates :refund_fee_percent,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :cancellation_window_hours,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 168 },
            allow_nil: true
  validates :tour_widget_thank_you_url,
            allow_blank: true,
            format: {
              with: %r{\Ahttps?://},
              message: "must start with http:// or https://"
            }

  RESERVED_SUBDOMAINS = %w[app www api admin mail ftp smtp staging demo support help status assets cdn dashboard root].freeze
  SUBDOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/

  validates :subdomain, presence: true
  validates :subdomain,
            format: { with: SUBDOMAIN_FORMAT, message: "must be lowercase letters, numbers, and hyphens (no leading/trailing hyphen)" },
            uniqueness: { case_sensitive: false },
            exclusion: { in: RESERVED_SUBDOMAINS, message: "is reserved" },
            if: :will_save_change_to_subdomain?

  BRAND_HEX_COLOR = /\A#?[0-9a-fA-F]{6}\z/
  validates :primary_color, format: { with: BRAND_HEX_COLOR }, allow_blank: true
  validates :accent_color, format: { with: BRAND_HEX_COLOR }, allow_blank: true
  HEX_COLOR_MESSAGE = "must be a hex color like #16a34a".freeze
  validates :embed_accent_override, format: { with: BRAND_HEX_COLOR, message: HEX_COLOR_MESSAGE }, allow_blank: true
  validates :showcase_button_color, format: { with: BRAND_HEX_COLOR, message: HEX_COLOR_MESSAGE }, allow_blank: true
  # People paste colors in every shape ("#FFF", " 16a34a ", "#16A34A;"): tidy
  # the widget colors before the format check so only real non-colors fail.
  before_validation :normalize_widget_colors

  def normalize_widget_colors
    self.embed_accent_override = self.class.tidy_hex(embed_accent_override)
    self.showcase_button_color = self.class.tidy_hex(showcase_button_color)
  end

  def self.tidy_hex(value)
    return value if value.nil?

    hex = value.to_s.strip.delete_prefix("#").delete_suffix(";").strip
    hex = hex.chars.map { |c| c * 2 }.join if hex.match?(/\A\h{3}\z/)
    hex.blank? ? "" : "##{hex}"
  end

  has_many :announcements
  has_many :automated_workflows
  has_many :day_passes
  has_many :day_pass_types
  has_many :doors
  has_many :door_punches
  has_many :feed_items
  has_many :invoices
  has_many :leads
  has_many :member_feedbacks
  has_many :notes, dependent: :destroy
  has_many :operator_surveys
  has_many :organizations
  has_many :plan_categories
  has_many :plans
  has_many :rooms
  has_many :users
  has_many :offices
  has_many :office_leases
  has_many :campaigns, dependent: :destroy
  has_many :officernd_imports, dependent: :destroy
  has_many :locations
  accepts_nested_attributes_for :locations, allow_destroy: false
  has_many :weekly_updates
  has_many :product_email_templates
  has_many :product_email_sends

  has_rich_text :tour_widget_intro_html

  has_many :childcare_reservations, through: :locations
  has_many :child_profiles, through: :users
  has_many :events, through: :locations
  has_many :posts, through: :locations
  has_many :subscriptions, through: :plans

  has_one_attached :background_image
  has_one_attached :logo_image
  has_one_attached :terms_of_service
  has_one_attached :push_notification_certificate
  has_one_attached :android_push_notification_key
  has_one_attached :app_icon_image

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

  scope :production, -> { where(billing_state: "production") }
  scope :demo, -> { where(billing_state: "demo") }

  # Callbacks
  after_save :update_kisi_api_key_for_locations

  %w(rooms offices office_leases member_feedbacks feed_items doors).each do |resource|
    define_method "#{resource}_by_location" do |location|
      public_send(resource).where(location: location)
    end
  end

  def tour_widget_active?
    tour_widget_enabled? && locations.where(visible: true).exists?
  end

  def concierge_active?
    concierge_enabled? && locations.where(visible: true).exists?
  end

  # Square brand mark for small surfaces (favicon, Concierge chat avatar).
  # Falls back to the logo, which is often a wide wordmark that crops badly.
  def icon_image
    app_icon_image.attached? ? app_icon_image : logo_image
  end

  # Concierge copy — sensible brand-derived defaults so it works pre-config.
  def concierge_display_name
    concierge_assistant_name.presence || name
  end

  def concierge_greeting_text
    concierge_greeting.presence || "Hi 👋 Welcome to #{name}. What brings you in today?"
  end

  # Shared embed-theme — inherited brand identity + optional overrides. Used by
  # BOTH the Concierge and the tour widget so the two always look consistent.
  def embed_primary_color
    css_hex(primary_color) || "#111827"
  end

  def embed_accent_color
    css_hex(embed_accent_override) || css_hex(accent_color) || "#2563eb"
  end

  # Brand colors are stored with or without the leading "#" (BRAND_HEX_COLOR
  # accepts both) but CSS needs it — a bare "0d6efd" made every widget button
  # fall back to the browser default and looked like the color could not be
  # changed (2026-09-02).
  def css_hex(value)
    hex = value.to_s.strip.delete_prefix("#")
    hex.present? ? "##{hex}" : nil
  end

  # Showcase product buttons: their own color when set, else the shared accent.
  def embed_button_color
    css_hex(showcase_button_color) || embed_accent_color
  end

  def embed_font_family
    embed_font.presence || "system-ui, -apple-system, Segoe UI, Roboto, sans-serif"
  end

  def has_mobile_app_links?
    ios_url.present? && android_url.present?
  end

  def has_contact_info?
    contact_name.present? && contact_email.present? && contact_phone.present?
  end

  def email_enabled?
    email_enabled || Rails.env.development?
  end

  # Returns formatted "From" address for emails.
  # Uses operator's sender_email if set, otherwise falls back to Jellyswitch default.
  def sender_from_address
    if sender_email.present?
      "#{name} <#{sender_email}>"
    else
      'Jellyswitch <noreply@jellyswitch.com>'
    end
  end

  def demo?
    billing_state == "demo"
  end

  def production?
    billing_state == "production" || subdomain == "southlakecoworking"
  end

  def stripe_secret_key # moved to location
    if production? && subdomain != "southlakecoworking"
      Rails.configuration.stripe[:secret_key]
    else
      Rails.configuration.stripe[:test_secret_key]
    end
  end

  def stripe_operator # moved to location
    @stripe_operator ||= StripeOperator.new(self)
  end

  def reset_stripe_to_demo!
    update(
      stripe_user_id: ENV["STRIPE_ACCOUNT_ID"],
      stripe_publishable_key: nil,
      stripe_refresh_token: nil,
      stripe_access_token: nil,
      billing_state: "demo",
    )
  end

  def checkins
    Checkin.for_operator(self)
  end

  # Predicates for features (most of the below moved to location)

  def day_passes_enabled?
    day_pass_types.count > 0
  end

  def memberships_enabled?
    plans.individual.visible.available.count > 0
  end

  def onboarded?
    plans.count > 0 &&
    day_pass_types.count > 0 &&
    ((rooms_enabled? && rooms.count > 0) || true) &&
    (((door_integration_enabled? && doors.count > 0) || true) || locations.all? { |l| l.building_access_instructions.present? }) &&
    users.members.count > 0 &&
    stripe_user_id.present?
  end

  def has_active_office_leases?
    office_leases.active.count > 0
  end

  def update_kisi_api_key_for_locations
    locations.where(kisi_api_key: nil).update_all(kisi_api_key: kisi_api_key)
  end

  private

  class StripeOperator < SimpleDelegator # moved to location
    include StripeUtils
  end

  private_constant :StripeOperator # moved to location
end
