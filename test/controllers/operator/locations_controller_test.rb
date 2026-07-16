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

  # ---- Kisi API key must never render in plaintext (live door credentials) ----

  KISI_SECRET = "kisi_live_SECRET_KEY_9animal7"

  test "location detail page masks the Kisi key, never the raw secret" do
    @location.update_column(:kisi_api_key, KISI_SECRET)
    log_in @admin

    get location_path(@location), env: default_env
    assert_response :success
    assert_not_includes response.body, KISI_SECRET, "raw Kisi key leaked into the location page"
    assert_includes response.body, "kisi_••••mal7", "expected the masked last-4 hint"
  end

  test "edit form never renders the raw Kisi key into the value attribute" do
    @location.update_column(:kisi_api_key, KISI_SECRET)
    log_in @admin

    get edit_location_path(@location), env: default_env
    assert_response :success
    assert_not_includes response.body, KISI_SECRET, "raw Kisi key leaked into the edit form HTML"
  end

  test "blank Kisi field on update keeps the existing key (no accidental wipe)" do
    @location.update_column(:kisi_api_key, KISI_SECRET)
    log_in @admin

    patch location_path(@location, params: { location: { name: "Renamed", kisi_api_key: "" } }),
          env: default_env
    @location.reload
    assert_equal "Renamed", @location.name
    assert_equal KISI_SECRET, @location.kisi_api_key, "blank submit must not wipe the stored key"
  end

  test "a new Kisi value on update replaces the key" do
    @location.update_column(:kisi_api_key, KISI_SECRET)
    log_in @admin

    patch location_path(@location, params: { location: { kisi_api_key: "kisi_new_ROTATED_2222" } }),
          env: default_env
    assert_equal "kisi_new_ROTATED_2222", @location.reload.kisi_api_key
  end

end
