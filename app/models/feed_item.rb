# == Schema Information
#
# Table name: feed_items
#
#  id          :bigint(8)        not null, primary key
#  blob        :jsonb            not null
#  expense     :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          not null
#  user_id     :integer
#
# Indexes
#
#  index_feed_items_on_blob  (blob) USING gin
#

class FeedItem < ApplicationRecord
  searchkick
  has_many_attached :photos
  before_save :parse_amount!

  # Relationships
  belongs_to :operator
  belongs_to :user
  has_many :feed_item_comments

  validate :photo_files_accepted

  acts_as_tenant :operator

  scope :for_operator, -> (operator) { where(operator: operator).where("blob->> 'type' != ?", "new-user") }
  scope :expenses, -> { where(expense: true) }

  # Types of feed_items
  scope :member_feedbacks, -> { where("blob->> 'type' = ?", "feedback") }
  scope :reservations, -> { where("blob->> 'type' = ?", "reservation") }

  def search_data
    {
      text: text,
      type: type,
      amount: amount,
      user_name: user.present? ? user.name : "Anonymous",
      comments: feed_item_comments.map(&:comment),
      stripe_customer_id: user.present? ? user.stripe_customer_id : nil
    }
  end

  def text
    blob["text"]
  end

  def type
    blob["type"]
  end

  def amount
    blob["amount"]
  end

  def has_photos?
    photos.count > 0
  end

  def feed_photos
    photos.map do |photo|
      photo.variant(combine_options: {auto_orient: true})
    end
  end

  def thumbnails
    photos.map do |photo|
      photo.variant(resize: '180x180', auto_orient: true)
    end
  end

  def parse_amount!
    if self.text && self.text.downcase.include?("spent")
      self.expense = true

      amount = (text.scan(/\$\d+.*\d+/).first.tr!("$", "").to_f * 100).to_i
      blob["amount"] = amount
    end
  end

  # Lazy relationships

  def reservation
    reservation_id = blob["reservation_id"]
    if reservation_id.nil?
      nil
    else
      Reservation.unscoped.find(reservation_id)
    end
  end

  def member_feedback
    member_feedback_id = blob["member_feedback_id"]
    if member_feedback_id.nil?
      nil
    else
      MemberFeedback.unscoped.find(member_feedback_id)
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

  def subscription
    subscription_id = blob["subscription_id"]
    if subscription_id.nil?
      nil
    else
      Subscription.find(subscription_id)
    end
  end

  def invoice
    invoice_id = blob["invoice_id"]

    Invoice.find_by(id: invoice_id)
  end

  private

  VALID_ATTACHMENT_REGEX = /image\/(jpeg|jpg|png|gif)/

  def photo_files_accepted
    if photos.any? { |photo| !photo.content_type.match VALID_ATTACHMENT_REGEX }
      errors.add(:photos, 'must be of file type .jpeg, .jpg, .png, or .gif')
    end
  end
end
