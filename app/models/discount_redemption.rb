class DiscountRedemption < ApplicationRecord
  belongs_to :discount_code
  belongs_to :user
  belongs_to :discountable, polymorphic: true, optional: true
  belongs_to :operator
  acts_as_tenant :operator
end
