class Operator < ApplicationRecord
  has_many :member_feedbacks
  has_many :feed_items

  def has_contact_info?
    contact_name.present? && contact_email.present? && contact_phone.present?
  end
end
