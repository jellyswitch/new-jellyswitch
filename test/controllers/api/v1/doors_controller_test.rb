require "test_helper"

# Coverage for the manual /api/v1/doors/:id/unlock action.
# Added when Api::V1::DoorUnlocking concern was extracted so we have a
# safety net for behavior parity with the pre-refactor inline code.
class Api::V1::DoorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member     = users(:cowork_tahoe_member)
    @non_member = users(:cowork_tahoe_non_member)
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @door       = Door.create!(
      name:        "Cowork Tahoe Front",
      slug:        "ct-front-#{SecureRandom.hex(4)}",
      location:    @location,
      operator:    @operator,
      kisi_id:     99001,
      available:   true,
    )

    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status:  200,
      body:    { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  def headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "active member unlock logs manual DoorPunch" do
    assert_difference -> { DoorPunch.where(method: "manual").count }, 2 do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@member)
    end

    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    assert_requested :post, @kisi_url, times: 1
  end

  test "non-member is denied" do
    post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@non_member)
    assert_response :forbidden
    assert_not_requested :post, @kisi_url
  end
end
