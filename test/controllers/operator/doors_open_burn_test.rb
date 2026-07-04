require "test_helper"

# GET /doors/:door_id/open (Operator::DoorsController#open) — the legacy web
# door-open button. Access has always been gated by DoorPolicy#open?
# (allowed_in? admits bundle holders), but the action never burned a bundle
# day, so a bundle-only member entering from the web got unmetered entry.
# It now calls Billing::DayPassBundles::ConsumeOnEntry like every other
# unlock path (see Api::V1::DoorUnlocking#perform_unlock).
class Operator::DoorsOpenBurnTest < ActionDispatch::IntegrationTest
  setup do
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @member     = users(:cowork_tahoe_member)      # active subscription
    @non_member = users(:cowork_tahoe_non_member)  # coverage only via bundle
    @door       = Door.create!(
      name:      "Cowork Tahoe Side",
      slug:      "ct-side-#{SecureRandom.hex(4)}",
      location:  @location,
      operator:  @operator,
      kisi_id:   99003,
      available: true,
    )

    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status:  200,
      body:    { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )

    host! "#{@operator.subdomain}.example.com"
  end

  def open_door!
    get "/doors/#{@door.slug}/open", env: default_env
  end

  def create_active_bundle(user, passes: 5)
    DayPassBundle.create!(
      user:               user,
      billable:           user,
      operator:           @operator,
      location:           @location,
      day_pass_type:      day_pass_type(:cowork_tahoe_day_pass_type),
      quantity_purchased: passes,
      passes_remaining:   passes,
      purchased_at:       Time.current,
    )
  end

  test "bundle-only member opening from the web burns exactly one pass" do
    bundle = create_active_bundle(@non_member)
    log_in @non_member

    open_door!

    assert_response :redirect
    assert_equal 4, bundle.reload.passes_remaining
    assert_equal 1, DayPass.where(user: @non_member, location: @location, day: Date.current).count
    assert_requested :post, @kisi_url, times: 1
  end

  test "opening twice the same day burns only one pass" do
    bundle = create_active_bundle(@non_member)
    log_in @non_member

    open_door!
    open_door!

    assert_equal 4, bundle.reload.passes_remaining, "second entry same day must not burn again"
  end

  test "subscription member open does NOT burn a bundle pass" do
    bundle = create_active_bundle(@member)
    log_in @member

    open_door!

    assert_response :redirect
    assert_equal 5, bundle.reload.passes_remaining, "subscription-covered user must not spend a pass"
  end
end
