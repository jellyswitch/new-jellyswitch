require "test_helper"

class Onboarding::Import::ImportDayPassesTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member) # tim@jellyswitch.com
    @dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    @cm = { email: "Email", day_pass_type: "Type", day: "Date", complimentary: "Comp" }
    @mapping = { "Standard Day Pass" => @dpt.id }
    ActsAsTenant.current_tenant = @operator
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def import(rows, type_mapping: @mapping)
    Onboarding::Import::ImportDayPasses.call(
      location: @location, rows: rows, column_mapping: @cm, type_mapping: type_mapping,
    )
  end

  test "creates a historical day pass with the right attributes" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Standard Day Pass", "Date" => "2024-03-01", "Comp" => "yes" }]

    assert_difference -> { DayPass.count } => 1 do
      result = import(rows)
      assert result.success?, result.message
      assert_equal 1, result.report[:summary][:day_passes_created]
    end

    pass = DayPass.order(:id).last
    assert_equal @member, pass.user
    assert_equal @dpt.id, pass.day_pass_type_id
    assert_equal Date.new(2024, 3, 1), pass.day
    assert pass.complimentary
    assert_equal @location.id, pass.location_id
  end

  test "does NOT fire the welcome-drip side effect for imported passes" do
    User.any_instance.expects(:enroll_in_welcome_drip!).never

    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Standard Day Pass", "Date" => "2024-03-02" }]
    assert import(rows).success?
  end

  test "is idempotent — re-running does not duplicate" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Standard Day Pass", "Date" => "2024-03-03" }]
    import(rows)

    assert_no_difference -> { DayPass.count } do
      result = import(rows)
      assert_equal :skipped, result.report[:rows].first[:action]
      assert_includes result.report[:rows].first[:notes], "already imported"
    end
  end

  test "skips a row whose user cannot be resolved" do
    rows = [{ "Email" => "nobody@example.com", "Type" => "Standard Day Pass", "Date" => "2024-03-04" }]

    assert_no_difference -> { DayPass.count } do
      result = import(rows)
      assert_equal :skipped, result.report[:rows].first[:action]
    end
  end

  test "skips a row whose day-pass type is not mapped" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Type" => "Mystery Pass", "Date" => "2024-03-05" }]

    assert_no_difference -> { DayPass.count } do
      result = import(rows)
      assert_match(/not mapped/, result.report[:rows].first[:notes])
    end
  end
end
