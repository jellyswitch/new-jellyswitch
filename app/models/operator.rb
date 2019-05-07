# == Schema Information
#
# Table name: operators
#
#  id                     :bigint(8)        not null, primary key
#  android_url            :string
#  approval_required      :boolean          default(TRUE), not null
#  billing_state          :string           default("demo"), not null
#  building_address       :string           default("not set"), not null
#  contact_email          :string
#  contact_name           :string
#  contact_phone          :string
#  day_pass_cost_in_cents :integer          default(2500), not null
#  email_enabled          :boolean          default(FALSE), not null
#  ios_url                :string
#  kisi_api_key           :string
#  name                   :string           not null
#  snippet                :string           default("Generic snippet about the space"), not null
#  square_footage         :integer          default(0), not null
#  stripe_access_token    :string
#  stripe_publishable_key :string
#  stripe_refresh_token   :string
#  subdomain              :string           not null
#  wifi_name              :string           default("not set"), not null
#  wifi_password          :string           default("not set"), not null
#  working_day_end        :string           default("18:00"), not null
#  working_day_start      :string           default("09:00"), not null
#  working_hours_enabled  :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  stripe_user_id         :string
#

class Operator < ApplicationRecord
  has_many :day_passes
  has_many :day_pass_types
  has_many :doors
  has_many :feed_items
  has_many :invoices
  has_many :member_feedbacks
  has_many :operator_surveys
  has_many :organizations
  has_many :plans
  has_many :rooms
  has_many :users
  has_many :offices
  has_many :office_leases
  has_many :locations

  has_one_attached :background_image
  has_one_attached :logo_image
  has_one_attached :terms_of_service
  has_one_attached :push_notification_certificate

  delegate :create_stripe_customer,
           :retrieve_stripe_customer,
           :create_stripe_invoice_item,
           :create_stripe_invoice,
           :retrieve_stripe_invoice,
           :create_stripe_refund,
           :retrieve_stripe_refund,
           :create_stripe_subscription,
           :create_stripe_plan,
           :mark_invoice_paid,
           :create_or_update_customer_payment,
           to: :stripe_operator

  scope :production, -> { where(billing_state: "production") }
  scope :demo, -> { where(billing_state: "demo") }

  %w(rooms offices office_leases member_feedbacks feed_items doors).each do |resource|
    define_method "#{resource}_by_location" do |location|
      public_send(resource).where(location: location)
    end
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

  def demo?
    billing_state == "demo"
  end

  def production?
    billing_state == "production"
  end

  def stripe_secret_key
    if production?
      Rails.configuration.stripe[:secret_key]
    else
      Rails.configuration.stripe[:test_secret_key]
    end
  end

  def stripe_operator
    @stripe_operator ||= StripeOperator.new(self)
  end

  def reset_stripe_to_demo!
    update(
      stripe_user_id: ENV['STRIPE_ACCOUNT_ID'],
      stripe_publishable_key: nil,
      stripe_refresh_token: nil,
      stripe_access_token: nil,
      billing_state: "demo")
  end

  private

  class StripeOperator < SimpleDelegator
    include StripeUtils
  end

  private_constant :StripeOperator
end
