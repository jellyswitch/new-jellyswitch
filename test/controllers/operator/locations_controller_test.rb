require "test_helper"

class Operator::LocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @location = locations(:cowork_tahoe_location)
    @admin = users(:cowork_tahoe_admin)
    @general_manager = users(:cowork_tahoe_general_manager)
    @candidate = users(:cowork_tahoe_community_manager)
  end

  test "admin can assign space_host_id" do
    log_in @admin
    patch location_path(@location, params: { location: { space_host_id: @candidate.id } }),
          env: default_env
    assert_equal @candidate.id, @location.reload.space_host_id
  end

  test "general manager update is allowed but space_host_id is filtered out" do
    log_in @general_manager
    @location.update_column(:space_host_id, nil)
    patch location_path(@location, params: { location: { name: "GM Renamed", space_host_id: @candidate.id } }),
          env: default_env
    @location.reload
    assert_equal "GM Renamed", @location.name
    assert_nil @location.space_host_id
  end

end
