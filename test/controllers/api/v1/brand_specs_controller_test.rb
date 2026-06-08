require "test_helper"

class Api::V1::BrandSpecsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @operator.update!(primary_color: "#76B82A", accent_color: "#E8871E")
    ENV["BRAND_SPEC_TOKEN"] = "test-secret"
  end

  teardown { ENV.delete("BRAND_SPEC_TOKEN") }

  test "returns the brand-spec with a valid service token" do
    get "/api/v1/brand_spec", headers: {
      "Authorization" => "Bearer test-secret",
      "X-Operator-Subdomain" => @operator.subdomain
    }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @operator.subdomain, body["subdomain"]
    assert_equal "#76B82A", body.dig("colors", "primary")
    assert_equal "https://#{@operator.subdomain}.jellyswitch.com/api/v1", body["apiBase"]
  end

  test "401 without the service token" do
    get "/api/v1/brand_spec", headers: { "X-Operator-Subdomain" => @operator.subdomain }
    assert_response :unauthorized
  end

  test "404 for an unknown subdomain" do
    get "/api/v1/brand_spec", headers: {
      "Authorization" => "Bearer test-secret",
      "X-Operator-Subdomain" => "nope-not-real"
    }
    assert_response :not_found
  end
end
