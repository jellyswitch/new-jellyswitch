class Operator < ApplicationRecord
  has_many :member_feedbacks
  has_many :feed_items
  has_many :plans

  has_one_attached :background_image
  has_one_attached :logo_image

  def has_contact_info?
    contact_name.present? && contact_email.present? && contact_phone.present?
  end
end
