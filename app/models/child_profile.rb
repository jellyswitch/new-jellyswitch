class ChildProfile < ApplicationRecord
  belongs_to :user

  has_rich_text :notes

  has_one_attached :photo
end
