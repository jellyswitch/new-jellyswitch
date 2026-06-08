require "test_helper"

class BrandSpec::BuildTest < ActiveSupport::TestCase
  test "assembles the canonical brand-spec from an operator" do
    op = operators(:cowork_tahoe)
    op.update!(primary_color: "#76B82A", accent_color: "#E8871E")

    result = BrandSpec::Build.call(
      operator: op,
      app_icon_url: "https://cdn.example/app_icon.png",
      wordmark_url: nil
    )

    assert result.success?
    spec = result.brand_spec
    assert_equal op.subdomain.parameterize, spec[:key]
    assert_equal op.name, spec[:name]
    assert_equal op.subdomain, spec[:subdomain]
    assert_equal "https://#{op.subdomain}.jellyswitch.com/api/v1", spec[:apiBase]
    expected_bundle = "com.jellyswitch.#{op.subdomain.parameterize.delete('-')}"
    assert_equal expected_bundle, spec[:bundleId][:ios]
    assert_equal expected_bundle, spec[:bundleId][:android]
    assert_equal "#76B82A", spec[:colors][:primary]
    assert_equal "#E8871E", spec[:colors][:accent]
    assert_equal "#FFFFFF", spec[:splashBackground]
    assert_equal "https://cdn.example/app_icon.png", spec[:assets][:appIcon]
    assert_nil spec[:assets][:wordmark]
  end
end
