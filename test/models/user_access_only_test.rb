require "test_helper"

# "Access only" people (users.access_only) — couriers, cleaning staff, etc.
# They open their HOME space's doors (original_location) 24/7 without any
# membership, pass or reservation, but are not members: hidden from member
# lists, counts and marketing. The door leg must agree across every gate:
# Permissions#has_building_access? (Keys list), #allowed_in_for_door_access?
# (legacy web open) and Api::V1::DoorUnlocking#user_can_access_building?
# (every unlock) — the PR #668 lockstep invariant.
class UserAccessOnlyTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  class UnlockGate
    include Api::V1::DoorUnlocking
    public :user_can_access_building?
  end

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @saturday = Date.current.next_occurring(:saturday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00",
                        open_saturday: false, open_sunday: false)
      @other_location = create(:location, operator: @operator, name: "Fulton Annex",
                               time_zone: "Pacific Time (US & Canada)")
      @courier = create(:user, operator: @operator, name: "Courier Carl", email: "courier@example.com",
                        access_only: true, original_location: @location, current_location: @location)
      @member = create(:user, operator: @operator, name: "Regular Rita", email: "rita@example.com",
                       original_location: @location, current_location: @location)
    end
    @gate = UnlockGate.new
  end

  def at_2am_saturday(&block)
    travel_to(@zone.parse("#{@saturday} 02:00"), &block)
  end

  test "access-only person opens their own space's doors at 2 AM on a closed day, no membership" do
    at_2am_saturday do
      assert_not @courier.has_active_subscription?
      assert @courier.has_building_access?(@location)
      assert @gate.user_can_access_building?(@courier, @location)
      assert @courier.allowed_in_for_door_access?(@location)
    end
  end

  test "access-only person cannot open another space of the same operator" do
    at_2am_saturday do
      assert_not @courier.has_building_access?(@other_location)
      assert_not @gate.user_can_access_building?(@courier, @other_location)
      assert_not @courier.allowed_in_for_door_access?(@other_location)
    end
    travel_to @zone.parse("#{@saturday - 4} 10:00") do
      assert_not @courier.has_building_access?(@other_location)
      assert_not @gate.user_can_access_building?(@courier, @other_location)
    end
  end

  test "unapproved access-only person has no access" do
    @courier.update!(approved: false)
    at_2am_saturday do
      assert_not @courier.has_building_access?(@location)
      assert_not @gate.user_can_access_building?(@courier, @location)
    end
  end

  test "archived access-only person has no access" do
    @courier.update!(archived: true)
    at_2am_saturday do
      assert_not @courier.has_building_access?(@location)
      assert_not @gate.user_can_access_building?(@courier, @location)
      assert_not @courier.allowed_in_for_door_access?(@location)
    end
  end

  test "a regular person with no membership still has no access" do
    at_2am_saturday do
      assert_not @member.has_building_access?(@location)
      assert_not @gate.user_can_access_building?(@member, @location)
    end
  end

  test "excluding_access_only / access_only_people scopes" do
    ids = User.where(id: [@courier.id, @member.id])
    assert_equal [@member.id], ids.excluding_access_only.pluck(:id)
    assert_equal [@courier.id], ids.access_only_people.pluck(:id)
  end

  test "access-only people are never marketing_sendable or campaign recipients" do
    assert_not_includes User.marketing_sendable.pluck(:id), @courier.id
    assert_includes User.marketing_sendable.pluck(:id), @member.id

    campaign = Campaign.create!(operator: @operator, location: @location, name: "Promo",
                                campaign_type: "single", status: "draft", segment: {}, cool_down_days: 30)
    ids = campaign.build_recipient_query(@location, apply_spam_guard: false).pluck(:id)
    assert_includes ids, @member.id
    assert_not_includes ids, @courier.id
  end

  test "access-only people are left out of report member counts and the member CSV" do
    report = Jellyswitch::Report.new(@operator, @location)
    assert_not_includes report.all_members.pluck(:id), @courier.id
    assert_includes report.all_members.pluck(:id), @member.id

    signups_with = report.new_signups_count
    @courier.update_columns(access_only: false)
    assert_equal signups_with + 1, report.new_signups_count
    @courier.update_columns(access_only: true)

    assert_not_includes report.member_csv, "courier@example.com"
    assert_includes report.member_csv, "rita@example.com"
  end

  test "access-only people are not @mentionable or offered in member pickers" do
    assert_not_includes @operator.users.mentionable.pluck(:id), @courier.id
    assert_includes @operator.users.mentionable.pluck(:id), @member.id

    lease_ids = User.lease_options_for_select(@operator, @location).map(&:last)
    assert_not_includes lease_ids, @courier.id
  end
end
