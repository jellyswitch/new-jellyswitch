class CompDay < ApplicationRecord
  belongs_to :user
  belongs_to :operator
  belongs_to :location
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :subscription, optional: true
  acts_as_tenant :operator

  validates :occurred_on, presence: true

  # Comps whose day falls within [window_start, window_end) — end exclusive,
  # matching the half-open billing-period windows the Day Pool counts against.
  scope :for_period, ->(window_start, window_end) {
    where(occurred_on: window_start.to_date...window_end.to_date)
  }
end
