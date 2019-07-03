# typed: false
# == Schema Information
#
# Table name: locations
#
#  id                           :bigint(8)        not null, primary key
#  allow_hourly                 :boolean          default(FALSE), not null
#  billing_state                :string
#  building_access_instructions :string
#  building_address             :string
#  city                         :string
#  common_square_footage        :integer          default(0), not null
#  contact_email                :string
#  contact_name                 :string
#  contact_phone                :string
#  flex_square_footage          :integer          default(0), not null
#  hourly_rate_in_cents         :integer          default(0), not null
#  name                         :string
#  new_users_get_free_day_pass  :boolean          default(FALSE), not null
#  open_friday                  :boolean          default(TRUE), not null
#  open_monday                  :boolean          default(TRUE), not null
#  open_saturday                :boolean          default(FALSE), not null
#  open_sunday                  :boolean          default(FALSE), not null
#  open_thursday                :boolean          default(TRUE), not null
#  open_tuesday                 :boolean          default(TRUE), not null
#  open_wednesday               :boolean          default(TRUE), not null
#  snippet                      :string
#  square_footage               :integer
#  state                        :string
#  stripe_access_token          :string
#  stripe_publishable_key       :string
#  stripe_refresh_token         :string
#  time_zone                    :string           default("Pacific Time (US & Canada)"), not null
#  visible                      :boolean          default(TRUE), not null
#  wifi_name                    :string
#  wifi_password                :string
#  working_day_end              :string           default("18:00"), not null
#  working_day_start            :string           default("09:00"), not null
#  zip                          :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  operator_id                  :bigint(8)        not null
#  stripe_user_id               :string
#
# Indexes
#
#  index_locations_on_operator_id     (operator_id)
#  index_locations_on_state_and_city  (state,city)
#  index_locations_on_zip             (zip)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => operators.id)
#

class Location < ApplicationRecord
  belongs_to :operator
  acts_as_tenant :operator

  has_many :checkins
  has_many :doors
  has_many :rooms
  has_many :offices
  has_many :office_leases
  has_many :feed_items
  has_many :member_feedbacks

  has_one_attached :background_image
  has_one_attached :photo

  validates :working_day_start, presence: true
  validates :working_day_end, presence: true

  scope :visible, -> { where(visible: true) }

  def has_photo?
    background_image.attached?
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
end
