class FeedItem < ApplicationRecord
  # Relationships
  belongs_to :operator
  belongs_to :user

  acts_as_tenant :operator

  scope :for_operator, ->(operator) { where(operator_id: operator.id) }

  def text
    blob["text"]
  end

  def type
    blob["type"]
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
end
