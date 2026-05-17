class Note < ApplicationRecord
  acts_as_tenant :operator

  belongs_to :operator
  belongs_to :notable, polymorphic: true
  belongs_to :author, class_name: "User"

  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
