require "test_helper"

class EventPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  # Web parity with the mobile Api::V1::EventsController#create — members
  # and office-lease holders can now propose events (subject to admin
  # approval); see Events::Create which leaves approved_at nil for
  # non-admin submissions.
  def test_new
    assert_permit @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_create
    assert_permit @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  # A signed-in user with no subscription and no active lease (e.g. an
  # account that has only ever bought a day-pass, or a pending signup)
  # must still be blocked — the rule is "Members + Office members,"
  # not "anyone with an account."
  def test_create_blocks_users_without_membership_or_lease
    bare_user = User.create!(
      name: "Day Pass Only",
      email: "daypassonly+#{SecureRandom.hex(4)}@example.com",
      password: "password",
      phone: "555-555-5555",
      operator: operators(:cowork_tahoe),
      original_location: locations(:cowork_tahoe_location),
      role: "unassigned",
      admin: false,
      superadmin: false,
      approved: true,
      terms_accepted_at: Time.current,
    )

    context = UserContext.new(bare_user, operators(:cowork_tahoe), locations(:cowork_tahoe_location))
    refute EventPolicy.new(context, Event).create?,
      "user with no active membership or lease must not be able to propose events"
  end

  def test_edit
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_update
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end

  def test_destroy
    assert_not_permitted @member, Event
    assert_permit @admin, Event
    assert_permit @community_manager, Event
    assert_permit @general_manager, Event
  end
end