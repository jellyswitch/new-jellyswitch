# == Schema Information
#
# Table name: product_email_sends
#
#  id            :bigint(8)        not null, primary key
#  email_type    :string           not null
#  error_message :text
#  sendable_type :string           not null
#  sent_at       :datetime
#  status        :string           default("sent")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operator_id   :bigint(8)        not null
#  sendable_id   :bigint(8)        not null
#  user_id       :bigint(8)        not null
#
# Indexes
#
#  idx_product_email_sends_unique            (sendable_type,sendable_id,email_type) UNIQUE
#  index_product_email_sends_on_operator_id  (operator_id)
#  index_product_email_sends_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => operators.id)
#  fk_rails_...  (user_id => users.id)
#
class ProductEmailSend < ApplicationRecord
  acts_as_tenant :operator
  belongs_to :operator
  belongs_to :user
  belongs_to :sendable, polymorphic: true

  validates :email_type, presence: true

  scope :recent, -> { order(sent_at: :desc) }

  def self.already_sent?(sendable, email_type)
    where(sendable: sendable, email_type: email_type).exists?
  end
end
