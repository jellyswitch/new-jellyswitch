class Reservation < ApplicationRecord
  # Relationships
  belongs_to :room
  belongs_to :user

  def pretty_datetime
    datetime_in.strftime("%m/%d%Y at %l:%M%P")
  end
end
