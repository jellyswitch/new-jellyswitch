require 'test_helper'

class Operator::LandingControllerTest < ActionDispatch::IntegrationTest
  # Honeybadger regression: bots probe with subdomain-less hosts
  # (`Host: localhost`, raw IPs). `request.subdomains.first` is nil for those,
  # and the tenant resolver crashed on `nil.downcase` before its own presence
  # guard could run. A junk host must behave like any unknown subdomain —
  # no tenant, no 500.
  test "root with a subdomain-less host does not 500" do
    host! "localhost"
    get "/"
    assert response.status < 500, "expected non-5xx for bare host, got #{response.status}"
  end

  test "root with an unknown subdomain resolves no tenant and does not 500" do
    host! "nosuchbrand.example.com"
    get "/"
    assert response.status < 500, "expected non-5xx for unknown subdomain, got #{response.status}"
  end
end
