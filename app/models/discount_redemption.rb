# == Schema Information
#
# Table name: discount_redemptions
#
#  id                       :bigint(8)        not null, primary key
#  discount_amount_in_cents :integer          not null
#  discountable_type        :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  discount_code_id         :bigint(8)        not null
#  discountable_id          :bigint(8)
#  operator_id              :integer          not null
#  user_id                  :bigint(8)        not null
#
# Indexes
#
#  index_discount_redemptions_on_discount_code_id  (discount_code_id)
#  index_discount_redemptions_on_discountable      (discountable_type,discountable_id)
#  index_discount_redemptions_on_operator_id       (operator_id)
#  index_discount_redemptions_on_user_id           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (discount_code_id => discount_codes.id)
#  fk_rails_...  (user_id => users.id)
#
class DiscountRedemption < ApplicationRecord
  belongs_to :discount_code
  belongs_to :user
  belongs_to :discountable, polymorphic: true, optional: true
  belongs_to :operator
  acts_as_tenant :operator
end
