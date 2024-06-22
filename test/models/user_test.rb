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

class UserTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    office_leases(:office_23b_lease).delete
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

  test 'User#should_charge_for_reservation?(location) returns true if user is unassigned (role) and a member' do
    user = users(:cowork_tahoe_member)

    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns true if user is unassigned (role) and not a member' do
    user = users(:cowork_tahoe_non_member)

    assert user.should_charge_for_reservation?(@location) == true
  end

  test ':out_of_band and :card_updated attributes cannot both be true' do
    user = users(:cowork_tahoe_non_member)

    user.update(out_of_band: true, card_added: true)

    assert user.valid? == false
  end

  test ':out_of_band can be true, if :card_added is false' do
    user = users(:cowork_tahoe_non_member)

    user.update(card_added: false, out_of_band: true)
    assert user.valid? == true
  end

  test ':card_added can be true, if out_of_band is false' do
    user = users(:cowork_tahoe_non_member)

    user.update(card_added: true, out_of_band: false)
    assert user.valid? == true
  end

  test ':card_added and out_of_band can both be false' do
    user = users(:cowork_tahoe_non_member)

    user.update(card_added: false, out_of_band: false)
    assert user.valid? == true
  end

  test 'upcoming_or_ongoing_reservation should return the ongoing reservation if exist' do
    user = users(:cowork_tahoe_member)
    ongoing_reservation = reservations(:room_reservation)
    ongoing_reservation.update(datetime_in: Time.zone.now)

    assert_equal user.upcoming_or_ongoing_reservation, ongoing_reservation
  end

  test 'upcoming_or_ongoing_reservation should return the future reservation if no ongoing reservation exist' do
    user = users(:cowork_tahoe_member)
    future_reservation = reservations(:future_room_reservation)

    user.reservations.ongoing.destroy_all

    assert_equal user.upcoming_or_ongoing_reservation, future_reservation
  end
end
