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
#  confirmation_sent_at          :datetime
#  confirmation_token            :string
#  credit_balance                :integer          default(0), not null
#  email                         :string           not null
#  email_bounced                 :boolean          default(FALSE), not null
#  email_confirmed               :boolean          default(FALSE), not null
#  email_opted_out               :boolean          default(FALSE), not null
#  home_city                     :string
#  home_latitude                 :decimal(10, 7)
#  home_longitude                :decimal(10, 7)
#  home_state                    :string
#  home_zip                      :string
#  inactive_dismissed_at         :datetime
#  ios_token                     :string
#  last_active_at                :datetime
#  linkedin                      :string
#  marketing_consent             :boolean          default(FALSE), not null
#  marketing_suppressed          :boolean          default(FALSE), not null
#  marketing_suppressed_reason   :string
#  name                          :string
#  out_of_band                   :boolean          default(FALSE), not null
#  password_digest               :string
#  phone                         :string
#  preferred_meeting_duration    :integer          default(60)
#  remember_digest               :string
#  reset_digest                  :string
#  reset_sent_at                 :datetime
#  role                          :string           default("unassigned"), not null
#  slug                          :string
#  superadmin                    :boolean          default(FALSE), not null
#  terms_accepted_at             :datetime
#  twitter                       :string
#  website                       :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  current_location_id           :integer
#  operator_id                   :integer          default(2), not null
#  organization_id               :integer
#  original_location_id          :integer
#  point_of_contact_id           :bigint(8)
#  preferred_room_id             :bigint(8)
#  stripe_customer_id            :string
#
# Indexes
#
#  index_users_on_home_state_and_home_city       (home_state,home_city)
#  index_users_on_home_zip                       (home_zip)
#  index_users_on_operator_home_state_home_city  (operator_id,home_state,home_city)
#  index_users_on_operator_id                    (operator_id)
#  index_users_on_point_of_contact_id            (point_of_contact_id)
#  index_users_on_preferred_room_id              (preferred_room_id)
#
# Foreign Keys
#
#  fk_rails_...  (point_of_contact_id => users.id)
#
require 'test_helper'

class UserTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    office_leases(:office_23b_lease).delete
  end

  # :mentionable backs note @mentions — staff PLUS approved, non-archived
  # members (so notes can tag members, not just admins). Distinct from
  # :taggable, which stays staff-only for the profile "managed by" dropdown.
  test "User.mentionable includes staff and approved members" do
    op = operators(:cowork_tahoe)
    names = op.users.mentionable.pluck(:name)

    assert_includes names, "Dave Paola",        "admin (staff) should be mentionable"
    assert_includes names, "General Manager",   "GM (staff) should be mentionable"
    assert_includes names, "Community Manager", "CM (staff) should be mentionable"
    assert_includes names, "Tim C",             "approved member should be mentionable (#4)"
  end

  test "User.mentionable excludes archived and unapproved members, and superadmins" do
    op = operators(:cowork_tahoe)
    member = users(:cowork_tahoe_member) # "Tim C"

    member.update!(archived: true)
    refute_includes op.users.mentionable.pluck(:name), "Tim C", "archived member excluded"

    member.update!(archived: false, approved: false)
    refute_includes op.users.mentionable.pluck(:name), "Tim C", "unapproved member excluded"

    refute_includes op.users.mentionable.pluck(:name), "Superadmin", "superadmin excluded"
  end

  # Door punches flood the timeline. "Recent" should hide them EXCEPT the first
  # punch after each join/payment milestone; the full history lives in "Doors".
  test "recent_timeline_activities keeps only the first door punch after each join/payment" do
    op   = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)
    user.activities.delete_all

    t = Time.utc(2026, 1, 1, 9, 0)
    mk = ->(kind, offset) { Activity.create!(user: user, operator: op, kind: kind, occurred_at: t + offset) }

    early    = mk.call("door_punch", 0)             # before any anchor → hidden
    sub      = mk.call("subscription_started", 1.hour)
    first1   = mk.call("door_punch", 2.hours)       # first after membership → MILESTONE
    noise1   = mk.call("door_punch", 3.hours)       # hidden
    pay      = mk.call("payment_succeeded", 4.hours)
    first2   = mk.call("door_punch", 5.hours)       # first after payment → MILESTONE
    noise2   = mk.call("door_punch", 6.hours)       # hidden

    ids = user.milestone_door_punch_ids
    assert_includes ids, first1.id
    assert_includes ids, first2.id
    [early, noise1, noise2].each { |a| refute_includes ids, a.id }

    recent_ids = user.recent_timeline_activities.map(&:id)
    # Milestone punches + all non-door activities are present…
    [first1, first2, sub, pay].each { |a| assert_includes recent_ids, a.id }
    # …and the door-punch noise is hidden.
    [early, noise1, noise2].each { |a| refute_includes recent_ids, a.id }
  end

  test "recent_timeline_activities hides ALL door punches when there is no join/payment anchor" do
    op   = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)
    user.activities.delete_all
    t = Time.utc(2026, 1, 1, 9, 0)
    punch = Activity.create!(user: user, operator: op, kind: "door_punch", occurred_at: t)
    tour  = Activity.create!(user: user, operator: op, kind: "tour", occurred_at: t + 1.hour)

    recent_ids = user.recent_timeline_activities.map(&:id)
    assert_includes recent_ids, tour.id
    refute_includes recent_ids, punch.id
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

  test 'User#should_charge_for_reservation?(location) returns false if user is a community manager (role)' do
    user = users(:cowork_tahoe_community_manager)

    assert user.should_charge_for_reservation?(@location) == false
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

  test 'upcoming_or_ongoing_reservation should return the ongoing reservation of the location if exist' do
    user = users(:cowork_tahoe_member)
    ongoing_reservation = reservations(:room_reservation)
    ongoing_reservation.update(datetime_in: Time.zone.now)

    assert_equal user.upcoming_or_ongoing_reservation(ongoing_reservation.room.location.id), ongoing_reservation
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

  test 'relevant_admins_of_location should return all admins of the location' do
    users = User.relevant_admins_of_location(@location)
    assert_equal users.sort_by(&:id), [users(:cowork_tahoe_admin), users(:cowork_tahoe_superadmin)].sort_by(&:id)

    assert_equal User.relevant_admins_of_location(nil), []
  end

  # Regression: a superadmin who MANAGES a location but is currently switched
  # to a different location stopped receiving that location's notifications,
  # because superadmins were matched only by current_location_id. (Prod: David
  # managed Untethered's Tahoe location but was switched to Fulton, so day-pass
  # / signup pushes never reached him.) Match superadmins by managed location.
  test 'relevant_admins_of_location includes a superadmin managing the location even when switched elsewhere' do
    loc = locations(:cowork_tahoe_location)
    other = Location.create!(
      name: "Sibling Location", operator: loc.operator, visible: true,
      time_zone: "Pacific Time (US & Canada)", working_day_start: "09:00", working_day_end: "18:00",
    )
    superadmin = users(:cowork_tahoe_superadmin)
    superadmin.update!(current_location: other)
    LocationManagement.find_or_create_by!(user: superadmin, location: loc)

    ids = User.relevant_admins_of_location(loc).map(&:id)
    assert_includes ids, superadmin.id,
      "a superadmin who manages the location should be notified even when current_location is elsewhere"
  end

  # Regression: a user whose Operator record has been deleted (orphaned
  # operator_id) used to crash the after_commit :sync_to_mailchimp callback
  # with NoMethodError on nil — the destroy still committed, but the
  # request/job raised. Reproduced in prod 2026-05-25 destroying user 37092.
  test 'destroy does not raise when operator is missing' do
    user = users(:cowork_tahoe_non_member)
    user.update_column(:operator_id, 0)
    user.reload
    assert_nil user.operator

    assert_nothing_raised do
      user.destroy
    end
  end
end
