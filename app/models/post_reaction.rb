class PostReaction < ApplicationRecord
  ALLOWED_EMOJIS = ["👍", "❤️", "🎉", "😂", "🔥", "💯"].freeze

  belongs_to :post
  belongs_to :user

  validates :emoji, presence: true, inclusion: { in: ALLOWED_EMOJIS }
  validates :user_id, uniqueness: { scope: [:post_id, :emoji] }
end
