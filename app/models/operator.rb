class Operator < ApplicationRecord
  has_many :member_feedbacks

  def has_contact_info?
    contact_name.present? && contact_email.present? && contact_phone.present?
  end
end
