require "test_helper"

class KisiUnlockJobTest < ActiveJob::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @door     = Door.create!(
      name:      "Front",
      slug:      "f-#{SecureRandom.hex(4)}",
      location:  @location,
      operator:  @operator,
      kisi_id:   4242,
      available: true,
    )
    @user  = users(:cowork_tahoe_member)
    @punch = DoorPunch.create!(
      user: @user, door: @door, operator: @operator, method: "auto", status: "pending",
    )
    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
  end

  test "marks the punch unlocked on Kisi success" do
    stub_request(:post, @kisi_url).to_return(status: 200, body: { ok: true }.to_json)
    KisiUnlockJob.perform_now(@punch.id)
    assert_equal "unlocked", @punch.reload.status
  end

  test "marks the punch failed on Kisi error" do
    stub_request(:post, @kisi_url).to_return(status: 502, body: "bad gateway")
    KisiUnlockJob.perform_now(@punch.id)
    assert_equal "failed", @punch.reload.status
  end

  test "no-ops on a missing punch id" do
    assert_nothing_raised { KisiUnlockJob.perform_now(-1) }
  end
end
