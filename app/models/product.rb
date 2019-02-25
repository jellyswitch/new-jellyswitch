# == Schema Information
#
# Table name: products
#
#  id          :bigint(8)        not null, primary key
#  available   :boolean          default(TRUE), not null
#  name        :string           not null
#  price       :integer          default(0), not null
#  visible     :boolean          default(TRUE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          not null
#

class Product < ApplicationRecord
  belongs_to :operator
  acts_as_tenant :operator

  def pretty_price
    price.to_f / 100.0
  end
end
