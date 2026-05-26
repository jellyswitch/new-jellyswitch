# == Schema Information
#
# Table name: post_reactions
#
#  id         :bigint(8)        not null, primary key
#  emoji      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  post_id    :bigint(8)        not null
#  user_id    :bigint(8)        not null
#
# Indexes
#
#  index_post_reactions_on_post_id  (post_id)
#  index_post_reactions_on_user_id  (user_id)
#  index_post_reactions_unique      (post_id,user_id,emoji) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (post_id => posts.id)
#  fk_rails_...  (user_id => users.id)
#
class PostReaction < ApplicationRecord
  ALLOWED_EMOJIS = ["👍", "❤️", "🎉", "😂", "🔥", "💯"].freeze

  belongs_to :post
  belongs_to :user

  validates :emoji, presence: true, inclusion: { in: ALLOWED_EMOJIS }
  validates :user_id, uniqueness: { scope: [:post_id, :emoji] }
end
