require "test_helper"

# Turned-away Day Office demand → one management-feed card per member+day.
class DayOffices::RecordSoldOutTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                kind: "day_office", amount_in_cents: 7500,
                                included_meeting_room_minutes: 0, available: true, visible: true)
    @day = Date.current + 7
  end

  def sold_out_items
    FeedItem.unscoped.where(operator_id: @operator.id)
            .where("blob->>'type' = ?", "day-office-sold-out")
  end

  def record!
    DayOffices::RecordSoldOut.call(user: @member, day_pass_type: @type, day: @day,
                                   location: @location, operator: @operator)
  end

  test "creates a feed card naming the type and the missed day" do
    assert_difference -> { sold_out_items.count }, 1 do
      record!
    end

    item = sold_out_items.last
    assert_equal @member.id, item.user_id
    assert_equal @location.id, item.location_id
    assert_equal @type.id.to_s, item.blob["day_pass_type_id"].to_s
    assert_equal @day.iso8601, item.blob["day"]
    assert_includes item.blob["text"], "Day Office"
    assert_includes item.blob["text"], "sold out"
  end

  test "collapses retaps — one card per member and day" do
    record!
    assert_no_difference -> { sold_out_items.count } do
      record!
    end
  end

  test "a different missed day gets its own card" do
    record!
    assert_difference -> { sold_out_items.count }, 1 do
      DayOffices::RecordSoldOut.call(user: @member, day_pass_type: @type, day: @day + 1,
                                     location: @location, operator: @operator)
    end
  end

  test "nil user is a quiet no-op" do
    assert_no_difference -> { sold_out_items.count } do
      assert_nothing_raised do
        DayOffices::RecordSoldOut.call(user: nil, day_pass_type: @type, day: @day,
                                       location: @location, operator: @operator)
      end
    end
  end
end