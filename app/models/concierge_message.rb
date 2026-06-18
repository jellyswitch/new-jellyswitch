class ConciergeMessage < ApplicationRecord
  ROLES = %w[visitor staff bot].freeze

  belongs_to :concierge_conversation
  belongs_to :operator
  belongs_to :author, class_name: "User", optional: true # the staff member, for staff messages

  acts_as_tenant :operator

  validates :role, inclusion: { in: ROLES }
  validates :body, presence: true
end
