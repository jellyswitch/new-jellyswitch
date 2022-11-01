# == Schema Information
#
# Table name: users
#
#  id                            :bigint(8)        not null, primary key
#  admin                         :boolean          default(FALSE), not null
#  always_allow_building_access  :boolean          default(FALSE), not null
#  android_token                 :string
#  approved                      :boolean          default(FALSE), not null
#  archived                      :boolean          default(FALSE), not null
#  bill_to_organization          :boolean          default(FALSE), not null
#  bio                           :text
#  card_added                    :boolean          default(FALSE), not null
#  childcare_reservation_balance :integer          default(0), not null
#  credit_balance                :integer          default(0), not null
#  email                         :string           not null
#  ios_token                     :string
#  linkedin                      :string
#  name                          :string
#  out_of_band                   :boolean          default(FALSE), not null
#  password_digest               :string
#  phone                         :string
#  remember_digest               :string
#  reset_digest                  :string
#  reset_sent_at                 :datetime
#  role                          :string           default("unassigned"), not null
#  slug                          :string
#  superadmin                    :boolean          default(FALSE), not null
#  twitter                       :string
#  website                       :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  operator_id                   :integer          default(2), not null
#  organization_id               :integer
#  stripe_customer_id            :string
#
# Indexes
#
#  index_users_on_operator_id  (operator_id)
#
require 'test_helper'

class UserManagerTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
  end

  test 'User#should_charge_for_reservation?(location) returns false if user is an admin (role)' do
    user = users(:cowork_tahoe_admin)

    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns false if user is a superadmin (role)' do
    user = users(:cowork_tahoe_superadmin)
    
    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns false if user is a general manager (role)' do
    user = users(:cowork_tahoe_general_manager)
    
    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns true if user is a community manager (role)' do
    user = users(:cowork_tahoe_community_manager)
    
    assert user.should_charge_for_reservation?(@location) == true
  end

  test 'User#should_charge_for_reservation?(location) returns true if user is unassigned (role)' do
    user = users(:cowork_tahoe_member)
    
    assert user.should_charge_for_reservation?(@location) == true
  end
end
