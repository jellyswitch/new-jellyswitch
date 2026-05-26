# == Schema Information
#
# Table name: organizations
#
#  id                 :bigint(8)        not null, primary key
#  name               :string           not null
#  out_of_band        :boolean          default(TRUE), not null
#  slug               :string
#  visible            :boolean          default(TRUE), not null
#  website            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  billing_contact_id :integer
#  location_id        :integer
#  operator_id        :integer          default(1), not null
#  owner_id           :integer
#  stripe_customer_id :string
#
# Indexes
#
#  index_organizations_on_location_id  (location_id)
#  index_organizations_on_operator_id  (operator_id)
#
FactoryBot.define do
  factory :organization do
    association :owner, factory: :user
    association :billing_contact, factory: :user

    sequence(:name) { |n| "Organization #{n}" }
    sequence(:slug) { |n| "organization-#{n}" }
    website { "www.example.com" }
    out_of_band { true }
    stripe_customer_id { nil }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
  end
end
