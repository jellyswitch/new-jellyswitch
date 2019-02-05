class MemberFeedback < ApplicationRecord
  belongs_to :operator
  belongs_to :user

  acts_as_tenant :operator

  def anonymous?
    self.anonymous == true
  end
end
