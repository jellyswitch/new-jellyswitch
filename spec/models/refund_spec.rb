# == Schema Information
#
# Table name: refunds
#
#  id               :bigint(8)        not null, primary key
#  amount           :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  invoice_id       :bigint(8)
#  stripe_refund_id :string
#  user_id          :bigint(8)
#
# Indexes
#
#  index_refunds_on_invoice_id  (invoice_id)
#  index_refunds_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (user_id => users.id)
#

require 'rails_helper'

RSpec.describe Refund, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
