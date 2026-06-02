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

  test "logs a structured outcome line with the context and error codes on failure" do
    ENV.stubs(:[]).with("TURNSTILE_SECRET").returns("test-secret")
    stub_response = stub(body: { "success" => false, "error-codes" => ["invalid-input-response"] }.to_json)
    Faraday.stubs(:post).returns(stub_response)
    Rails.logger.expects(:info).with do |line|
      line.include?("turnstile_verification") &&
        line.include?("operator_signup") &&
        line.include?("invalid-input-response") &&
        line.include?("fail")
    end
    Turnstile::Verifier.call(token: "bad", remote_ip: "1.2.3.4", context: "operator_signup")
  end

  test "logs a structured pass line tagged with the mobile_signup context" do
    ENV.stubs(:[]).with("TURNSTILE_SECRET").returns("test-secret")
    stub_response = stub(body: { "success" => true }.to_json)
    Faraday.stubs(:post).returns(stub_response)
    Rails.logger.expects(:info).with do |line|
      line.include?("turnstile_verification") &&
        line.include?("mobile_signup") &&
        line.include?("pass")
    end
    Turnstile::Verifier.call(token: "good", remote_ip: "1.2.3.4", context: "mobile_signup")
  end

  test "does not log when verification short-circuits (secret unset)" do
    ENV.stubs(:[]).returns(nil)
    Rails.logger.expects(:info).never
    Turnstile::Verifier.call(token: "anything", remote_ip: "127.0.0.1", context: "operator_signup")
  end
end
