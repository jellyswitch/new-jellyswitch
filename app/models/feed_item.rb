# == Schema Information
#
# Table name: feed_items
#
#  id          :bigint(8)        not null, primary key
#  operator_id :integer          not null
#  user_id     :integer
#  blob        :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  expense     :boolean          default(FALSE), not null
#

class FeedItem < ApplicationRecord
  has_many_attached :photos
  before_save :parse_amount!

  # Relationships
  belongs_to :operator
  belongs_to :user

  acts_as_tenant :operator

  scope :for_operator, ->(operator) { where(operator_id: operator.id) }
  scope :expenses, ->() { where(expense: true) }

  def text
    blob["text"]
  end

  def type
    blob["type"]
  end

  def amount
    blob["amount"]
  end

  def reservation
    reservation_id = blob["reservation_id"]
    if reservation_id.nil?
      nil
    else
      Reservation.find(reservation_id)
    end
  end

  def member_feedback
    member_feedback_id = blob["member_feedback_id"]
    if member_feedback_id.nil?
      nil
    else
      MemberFeedback.find(member_feedback_id)
    end
  end

  def has_photos?
    photos.count > 0
  end

  def thumbnails
    photos.map do |photo|
      photo.variant(resize: '180x180', auto_orient: true)
    end
  end

  def day_pass
    day_pass_id = blob["day_pass_id"]
    if day_pass_id.nil?
      nil
    else
      DayPass.find(day_pass_id)
    end
  end

  def parse_amount!
    if expense?
      amount = (text.scan(/\$\d+.*\d+/).first.tr!("$", "").to_f * 100).to_i
      blob["amount"] = amount
    end
  end
end
