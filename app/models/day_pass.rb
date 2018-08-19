class DayPass < ApplicationRecord
  # Relationships
  belongs_to :user

  # Scopes
  scope :today, ->() { where(day: Time.current) }

  # Instance methods
  def pretty_day
    day.strftime("%m/%d/%Y")
  end
end
