require 'test_helper'

class Turnstile::VerifierTest < ActiveSupport::TestCase
  test "short-circuits to success when TURNSTILE_SECRET is blank" do
    ENV.stubs(:[]).returns(nil)
    result = Turnstile::Verifier.call(token: "anything", remote_ip: "127.0.0.1")
    assert result.success?
  end

  test "returns success when Cloudflare reports valid token" do
    ENV.stubs(:[]).with("TURNSTILE_SECRET").returns("test-secret")
    stub_response = stub(body: { "success" => true }.to_json)
    Faraday.stubs(:post).returns(stub_response)
    result = Turnstile::Verifier.call(token: "good-token", remote_ip: "1.2.3.4")
    assert result.success?
  end

  test "returns failure when Cloudflare reports invalid token" do
    ENV.stubs(:[]).with("TURNSTILE_SECRET").returns("test-secret")
    stub_response = stub(body: { "success" => false, "error-codes" => ["invalid-input-response"] }.to_json)
    Faraday.stubs(:post).returns(stub_response)
    result = Turnstile::Verifier.call(token: "bad-token", remote_ip: "1.2.3.4")
    refute result.success?
    assert_includes result.error_codes, "invalid-input-response"
  end

  test "fails closed on network error and reports to Honeybadger" do
    ENV.stubs(:[]).with("TURNSTILE_SECRET").returns("test-secret")
    Honeybadger.expects(:notify).at_least_once
    Faraday.stubs(:post).raises(Faraday::ConnectionFailed.new("boom"))
    result = Turnstile::Verifier.call(token: "x", remote_ip: "1.2.3.4")
    refute result.success?
  end
end
