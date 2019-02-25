# == Schema Information
#
# Table name: operators
#
#  id                         :bigint(8)        not null, primary key
#  approval_required          :boolean          default(TRUE), not null
#  building_address           :string           default("not set"), not null
#  contact_email              :string
#  contact_name               :string
#  contact_phone              :string
#  day_pass_cost_in_cents     :integer          default(2500), not null
#  email_enabled              :boolean          default(FALSE), not null
#  name                       :string           not null
#  snippet                    :string           default("Generic snippet about the space"), not null
#  square_footage             :integer          default(0), not null
#  subdomain                  :string           not null
#  wifi_name                  :string           default("not set"), not null
#  wifi_password              :string           default("not set"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  stripe_day_pass_product_id :string
#

class Operator < ApplicationRecord
  has_many :day_passes
  has_many :feed_items
  has_many :invoices
  has_many :member_feedbacks
  has_many :organizations
  has_many :plans
  has_many :users

  has_one_attached :background_image
  has_one_attached :logo_image

  def has_contact_info?
    contact_name.present? && contact_email.present? && contact_phone.present?
  end

  def email_enabled?
    email_enabled || Rails.env.development?
  end
end
