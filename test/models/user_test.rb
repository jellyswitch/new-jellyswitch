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

  # A day pass covers free rooms + included minutes, NOT premium hourly rooms.
  # should_charge_for_room? must charge day-passers for premium rooms while still
  # exempting members/staff and never charging for free rooms.
  test "should_charge_for_room? charges day-passers for premium rooms, exempts staff/free" do
    op = operators(:cowork_tahoe)
    op.update!(billing_state: "production")
    premium   = rooms(:large_meeting_room); premium.update!(hourly_rate_in_cents: 5000)
    free_room = rooms(:small_meeting_room); free_room.update!(hourly_rate_in_cents: 0)

    day_passer = users(:cowork_tahoe_non_member)
    create(:day_pass, user: day_passer, operator: op) # complimentary:false => purchased day pass for today

    assert day_passer.should_charge_for_room?(premium),    "day-passer must pay for a premium room (the leak fix)"
    refute day_passer.should_charge_for_room?(free_room),  "free rooms are never charged hourly"
    refute users(:cowork_tahoe_admin).should_charge_for_room?(premium), "admin/staff are comped"
  end

  # A Day Pass Bundle holder has prepaid passes, so they may book a room in
  # ADVANCE (e.g. tomorrow) — they burn a pass on entry. can_see_all_rooms?
  # gates whether free/call rooms are visible; it must treat an active bundle as
  # standing, not just a DayPass already minted for the requested day (which a
  # bundle never has for a future date — no scheduling).
  test "can_see_all_rooms? reveals all rooms to a bundle holder for a future date" do
    op       = operators(:cowork_tahoe); op.update!(billing_state: "production")
    location = locations(:cowork_tahoe_location)
    user     = users(:cowork_tahoe_non_member)
    tomorrow = Date.tomorrow

    refute user.can_see_all_rooms?(location, tomorrow), "no coverage for tomorrow yet → restricted to rentable rooms"

    DayPassBundle.create!(
      user: user, billable: user, operator: op, location: location,
      day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type),
      quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current,
    )

    assert user.can_see_all_rooms?(location, tomorrow),
      "an active bundle is standing to see all rooms — they burn a pass on entry"
  end

  # --- Per-plan monthly meeting-room limit (included_meeting_room_minutes) ---
  # The included-minutes pool covers FREE standard rooms at THIS location only.

  # Gap A: premium/paid rooms are billed hourly separately, so their minutes
  # must NOT also burn the free allowance (mirrors the day-pass path).
  test "subscription_reservation_charge_info excludes paid-room minutes from the used pool (Gap A)" do
    member = users(:cowork_tahoe_member)
    Reservation.where(user_id: member.id).delete_all
    plans(:cowork_tahoe_full_time_plan).update!(
      included_meeting_room_minutes: 120, overage_rate_in_cents: 6000, location_id: @location.id,
    )
    free_room = rooms(:small_meeting_room); free_room.update!(hourly_rate_in_cents: 0, location: @location)
    paid_room = rooms(:large_meeting_room); paid_room.update!(hourly_rate_in_cents: 5000, location: @location)

    Reservation.create!(user: member, room: free_room, datetime_in: 1.day.from_now.change(hour: 9),  minutes: 60, cancelled: false)
    Reservation.create!(user: member, room: paid_room, datetime_in: 1.day.from_now.change(hour: 14), minutes: 60, cancelled: false)

    info = member.subscription_reservation_charge_info(@location, 30)
    assert_equal 60, info[:used_minutes],   "only the free-room 60 min should burn the pool; the paid room is billed hourly"
    assert_equal 60, info[:remaining_free], "remaining = 120 included - 60 free-room minutes used"
  end

  # Gap C: the allowance is location-specific, so a member's bookings at the
  # operator's OTHER locations must not count against this location's pool.
  test "subscription_reservation_charge_info is scoped to the location's rooms (Gap C)" do
    member = users(:cowork_tahoe_member)
    Reservation.where(user_id: member.id).delete_all
    plans(:cowork_tahoe_full_time_plan).update!(
      included_meeting_room_minutes: 120, overage_rate_in_cents: 6000, location_id: @location.id,
    )
    here = rooms(:small_meeting_room); here.update!(hourly_rate_in_cents: 0, location: @location)

    other_loc = Location.create!(
      name: "Sibling Location", operator: @location.operator, visible: true,
      time_zone: "Pacific Time (US & Canada)", working_day_start: "09:00", working_day_end: "18:00",
    )
    there = Room.create!(
      name: "Other-Loc Room", operator: @location.operator, location: other_loc,
      hourly_rate_in_cents: 0, visible: true, rentable: true,
    )

    Reservation.create!(user: member, room: here,  datetime_in: 1.day.from_now.change(hour: 9),  minutes: 60, cancelled: false)
    Reservation.create!(user: member, room: there, datetime_in: 1.day.from_now.change(hour: 14), minutes: 60, cancelled: false)

    info = member.subscription_reservation_charge_info(@location, 30)
    assert_equal 60, info[:used_minutes], "only the 60 min booked at THIS location should count against its pool"
  end

  # ---- Day Pool gates BUILDING ACCESS only, not membership identity (ADR 0004) ----

  def setup_day_limited_member(limit:, punch_days:)
    member = users(:cowork_tahoe_member)
    sub = subscriptions(:cowork_tahoe_subscription)
    sub.update!(stripe_subscription_id: nil, start_date: 5.days.ago)
    sub.plan.update!(has_day_limit: true, day_limit: limit,
                     always_allow_building_access: true, location_id: @location.id)
    door = Door.create!(name: "D#{SecureRandom.hex(3)}", slug: "d-#{SecureRandom.hex(4)}",
                        operator: operators(:cowork_tahoe), location: @location)
    punch_days.each do |d|
      p = DoorPunch.create!(user: member, door: door, operator: operators(:cowork_tahoe))
      p.update_column(:created_at, d.days.ago.change(hour: 9))
    end
    member
  end

  test "exhausting the day pool keeps membership but drops membership building access" do
    member = setup_day_limited_member(limit: 2, punch_days: [1, 2]) # 2 of 2 used, none today

    assert member.has_active_subscription?,
      "still a Member when out of days — identity must not be revoked"
    assert member.has_active_subscription_at_location?(@location),
      "room visibility / membership at location stays intact"
    refute member.has_building_access_membership?,
      "but membership no longer grants building access — the day pool is exhausted"
  end

  test "a day-limited member under the limit keeps membership building access" do
    member = setup_day_limited_member(limit: 5, punch_days: [1]) # 1 of 5 used

    assert member.has_active_subscription?
    assert member.has_building_access_membership?
  end

  # Hour Pool is date-aware: a reservation draws from the pool of the billing
  # period it FALLS IN, not the period it was booked in. Booking for next month
  # sees next month's fresh pool even if this month's pool is exhausted.
  test "subscription_reservation_charge_info draws from the period the reservation falls in (date-aware)" do
    member = users(:cowork_tahoe_member)
    Reservation.where(user_id: member.id).delete_all
    subscriptions(:cowork_tahoe_subscription).update!(stripe_subscription_id: nil, start_date: 5.days.ago)
    plans(:cowork_tahoe_full_time_plan).update!(
      included_meeting_room_minutes: 120, overage_rate_in_cents: 6000, location_id: @location.id,
    )
    free_room = rooms(:small_meeting_room); free_room.update!(hourly_rate_in_cents: 0, location: @location)

    # Exhaust THIS period (120 of 120 used).
    Reservation.create!(user: member, room: free_room, datetime_in: 1.day.from_now.change(hour: 9), minutes: 120, cancelled: false)

    this_period = member.subscription_reservation_charge_info(@location, 60, room: free_room, at: 1.day.from_now)
    assert_equal 120, this_period[:used_minutes], "this period is exhausted"
    assert_equal :partial_overage, this_period[:charge_type]

    next_period = member.subscription_reservation_charge_info(@location, 60, room: free_room, at: 40.days.from_now)
    assert_equal 0, next_period[:used_minutes], "next period's pool is fresh — this period's bookings don't count"
    assert_equal :free, next_period[:charge_type]
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

  # A freshly-created operator admin must be linked to their operator's
  # location(s) so direct readers of managed_location_ids (e.g. the admin API's
  # location scoping) work. Onboarding previously created no location_managements
  # row, which locked new operator admins out of room/door admin.
  test "a newly created admin is auto-linked to all of their operator's locations" do
    operator = operators(:cowork_tahoe)
    loc1 = operator.locations.first
    loc2 = create(:location, operator: operator, name: "Second Location",
                  working_day_start: "00:00", working_day_end: "23:59")

    admin = create(:user, operator: operator, role: "admin", email: "fresh-admin@example.com")

    assert_equal [loc1.id, loc2.id].sort, admin.managed_location_ids.sort
  end

  test "a newly created member is not auto-linked to any location" do
    operator = operators(:cowork_tahoe)
    member = create(:user, operator: operator, role: "unassigned", email: "fresh-member@example.com")

    assert_empty member.managed_location_ids
  end

  test "an admin created with explicit managed locations is not overwritten" do
    operator = operators(:cowork_tahoe)
    loc1 = operator.locations.first
    create(:location, operator: operator, name: "Second Location",
           working_day_start: "00:00", working_day_end: "23:59")

    admin = create(:user, operator: operator, role: "admin",
                   managed_locations: [loc1], email: "scoped-admin@example.com")

    assert_equal [loc1.id], admin.managed_location_ids
  end

  # Duplicate-account regression: downcasing ran before_save — AFTER the
  # case-sensitive uniqueness check — so "Foo@x.com" validated clean against
  # a stored "foo@x.com", then saved as an exact duplicate row. One member's
  # autocapitalized web signups minted three identical accounts.
  test "email uniqueness ignores case within an operator" do
    operator = operators(:cowork_tahoe)
    create(:user, operator: operator, email: "evelyn@example.com")

    dupe = build(:user, operator: operator, email: "Evelyn@Example.com")
    refute dupe.valid?, "differently-cased duplicate email must not validate"
    assert dupe.errors[:email].any?
  end

  test "email normalizes to lowercase at validation time" do
    user = create(:user, operator: operators(:cowork_tahoe), email: "MixedCase@Example.com")
    assert_equal "mixedcase@example.com", user.email
  end

  # Prod incident (untethered, 2026-07-13): "scott.screenzen.co" — the @ typo'd
  # away — passed every email validation (presence, uniqueness, disposable, MX)
  # and only died at Stripe::Customer.create.
  test "email without an @ is rejected on create with a clear message" do
    user = build(:user, operator: operators(:cowork_tahoe), email: "scott.screenzen.co")
    refute user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "email with spaces, a missing part, or a second @ is rejected on create" do
    ["scott @screenzen.co", "scott@screenzen@co", "@screenzen.co", "scott@"].each do |email|
      user = build(:user, operator: operators(:cowork_tahoe), email: email)
      refute user.valid?, "#{email.inspect} must not validate"
      assert_includes user.errors[:email], "is invalid"
    end
  end

  test "@-less email hits the format error, not a bogus disposable-domain match" do
    # Pre-fix, "bob.mailinator.com" (no @) end_with-matched ".mailinator.com"
    # as if the whole string were a domain, yielding the misleading
    # "temporary email provider" error instead of "is invalid".
    user = build(:user, operator: operators(:cowork_tahoe), email: "bob.mailinator.com")
    refute user.valid?
    assert_includes user.errors[:email], "is invalid"
    refute_match(/temporary/i, user.errors[:email].join)
  end

  test "format check is create-only so legacy rows with malformed emails still save" do
    user = create(:user, operator: operators(:cowork_tahoe), email: "legacy@example.com")
    # Simulate a malformed email persisted before the format validation existed.
    user.update_column(:email, "legacy.example.com")

    assert user.reload.update(name: "Still Updatable"),
           "existing malformed-email row must not be bricked: #{user.errors.full_messages}"
  end

  test "database unique index rejects duplicate emails even when validations are skipped" do
    operator = operators(:cowork_tahoe)
    create(:user, operator: operator, email: "backstop@example.com")

    # validate: false also skips before_validation normalization — the
    # lower(email) expression index must still catch the duplicate.
    dupe = build(:user, operator: operator, email: "Backstop@Example.com")
    assert_raises(ActiveRecord::RecordNotUnique) { dupe.save(validate: false) }
  end

  # feed_items has no DB foreign key to users; without dependent cleanup a
  # deleted user's feed items linger with a nil `user` and 500 the operator
  # feed (TLH login outage, 2026-07-20).
  test "destroying a user destroys their feed items and comments" do
    user = create(:user, operator: operators(:cowork_tahoe))
    item = FeedItem.create!(operator: operators(:cowork_tahoe), user: user, blob: { type: "checkin" })
    comment = FeedItemComment.create!(feed_item: item, user: user, comment: "hi")

    user.destroy!

    assert_not FeedItem.exists?(item.id)
    assert_not FeedItemComment.exists?(comment.id)
  end

  test "Users::Save turns a unique-index rejection into a graceful failure" do
    User.any_instance.stubs(:save).raises(ActiveRecord::RecordNotUnique.new("duplicate key"))

    result = Users::Save.call(
      params: { name: "Race Condition", email: "race@example.com", password: "secret1" },
      operator: operators(:cowork_tahoe),
      admin_created: false,
    )

    refute result.success?
    assert_match "already been taken", result.message
  end
end
