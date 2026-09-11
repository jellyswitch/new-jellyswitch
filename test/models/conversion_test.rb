require "test_helper"

class ConversionTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
    @admin = users(:cowork_tahoe_admin)
    @member.update_columns(acquired_at: nil, acquisition_channel: nil)
  end

  test "record snapshots the buyer's first-touch and marks self-serve when the buyer acts" do
    visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "vt", user: @member,
                                started_at: 1.day.ago, referrer: "https://www.google.com/")
    day_pass = DayPass.new(id: 987_654)

    row = Conversion.record(kind: "day_pass", operator: @operator, location: @location, user: @member,
                            subject: day_pass, amount_cents: 3500, surface: "web", actor: @member, visit: visit)

    assert row.persisted?
    assert_equal "organic_search", row.channel
    assert_equal "organic_search", @member.reload.acquisition_channel
    assert row.self_serve
    assert_equal 35.0, row.amount
    assert_equal visit.id, row.ahoy_visit_id
  end

  test "record is not self-serve when staff act for a member, and dedupes on subject + kind" do
    day_pass = DayPass.new(id: 987_655)
    first = Conversion.record(kind: "day_pass", operator: @operator, user: @member, subject: day_pass,
                              amount_cents: 0, surface: "web", actor: @admin)
    assert_not first.self_serve

    again = Conversion.record(kind: "day_pass", operator: @operator, user: @member, subject: day_pass,
                              amount_cents: 0, surface: "web", actor: @admin)
    assert_equal first.id, again.id
    assert_equal 1, Conversion.where(subject: day_pass).count
  end

  test "record never raises into the caller" do
    assert_nil Conversion.record(kind: "bogus", operator: @operator, user: @member)
    assert_nil Conversion.record(kind: "signup", operator: nil, user: @member)
  end
end
