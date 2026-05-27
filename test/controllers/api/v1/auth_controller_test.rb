require "test_helper"

# Coverage for /api/v1/auth/operators — the public catalog endpoint that
# powers the signup-screen "Choose your space" picker on the React Native
# mobile app. Used to return every operator in the jellyswitch ecosystem
# with no scoping, which leaked cross-brand operators (Innogrove, InSpark,
# Studio) and any low-quality / spammy operator signups into branded apps'
# pickers. Now hard-scoped to the requesting X-Operator-Subdomain header.
class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
  end

  test "operators returns only the requesting brand when X-Operator-Subdomain is set" do
    get "/api/v1/auth/operators",
        headers: { "X-Operator-Subdomain" => @operator.subdomain }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["operators"].length
    assert_equal @operator.subdomain, body["operators"].first["subdomain"]
    assert_equal @operator.name,      body["operators"].first["name"]
  end

  test "operators returns an empty array when no subdomain header is sent" do
    get "/api/v1/auth/operators"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["operators"]
  end

  test "operators returns an empty array when the subdomain header is unknown" do
    get "/api/v1/auth/operators",
        headers: { "X-Operator-Subdomain" => "no-such-operator" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["operators"]
  end

  test "operators includes the visible locations for the requesting brand" do
    get "/api/v1/auth/operators",
        headers: { "X-Operator-Subdomain" => @operator.subdomain }

    body = JSON.parse(response.body)
    op = body["operators"].first
    assert op["locations"].is_a?(Array)
    refute op["locations"].empty?, "expected at least one visible location for #{@operator.subdomain}"
    op["locations"].each do |loc|
      assert loc["id"].present?
      assert loc["name"].present?
    end
  end
end
