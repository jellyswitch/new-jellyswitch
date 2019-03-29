# == Schema Information
#
# Table name: operators
#
#  id                     :bigint(8)        not null, primary key
#  approval_required      :boolean          default(TRUE), not null
#  billing_state          :string           default("demo"), not null
#  building_address       :string           default("not set"), not null
#  contact_email          :string
#  contact_name           :string
#  contact_phone          :string
#  day_pass_cost_in_cents :integer          default(2500), not null
#  email_enabled          :boolean          default(FALSE), not null
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

  has_one_attached :background_image
  has_one_attached :logo_image
  has_one_attached :terms_of_service
  has_one_attached :push_notification_certificate

  delegate :retrieve_stripe_invoice, :create_stripe_refund, to: :stripe_operator

  scope :production, -> { where(billing_state: "production") }

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

  private

  class StripeOperator < SimpleDelegator
    include StripeUtils
  end

  private_constant :StripeOperator
end
