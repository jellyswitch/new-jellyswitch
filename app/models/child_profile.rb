class ChildProfile < ApplicationRecord
  belongs_to :user

  has_rich_text :notes

  has_one_attached :photo

  def thumbnail
    photo.variant(resize: "180x180", auto_orient: true)
  end
end
