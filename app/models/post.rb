# == Schema Information
#
# Table name: posts
#
#  id          :bigint(8)        not null, primary key
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_posts_on_location_id  (location_id)
#

class Post < ApplicationRecord
  include HasLocation

  belongs_to :location
  belongs_to :user
  delegate :operator, to: :location

  has_many :post_replies, dependent: :destroy
  has_many :post_reactions, dependent: :destroy

  has_rich_text :content
end
