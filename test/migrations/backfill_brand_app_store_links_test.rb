require "test_helper"
require Rails.root.join("db/migrate/20260625000001_backfill_brand_app_store_links.rb").to_s

# The backfill must fill BLANK per-brand store links (so the app hand-off + email
# badges render) without ever clobbering a value an operator already set, and must
# repair the one known-dead Cowork Tahoe Android link (non-".v2" package 404s).
class BackfillBrandAppStoreLinksTest < ActiveSupport::TestCase
  setup { @op = operators(:cowork_tahoe) } # subdomain "tml"

  test "fills a brand's blank app links" do
    @op.update_columns(ios_url: nil, android_url: nil)

    BackfillBrandAppStoreLinks.new.up

    @op.reload
    assert_equal "https://apps.apple.com/us/app/cowork-tahoe-the-lab/id1457603889", @op.ios_url
    assert_equal "https://play.google.com/store/apps/details?id=com.jellyswitch.coworktahoe.v2", @op.android_url
  end

  test "does not clobber links an operator already set" do
    @op.update_columns(
      ios_url:     "https://apps.apple.com/us/app/custom/id999",
      android_url: "https://play.google.com/store/apps/details?id=com.jellyswitch.coworktahoe.v2",
    )

    BackfillBrandAppStoreLinks.new.up

    @op.reload
    assert_equal "https://apps.apple.com/us/app/custom/id999", @op.ios_url
  end

  test "repairs the dead non-v2 Cowork Tahoe android link" do
    @op.update_columns(android_url: "https://play.google.com/store/apps/details?id=com.jellyswitch.coworktahoe&pcampaignid=MKT-x")

    BackfillBrandAppStoreLinks.new.up

    @op.reload
    assert_includes @op.android_url, "com.jellyswitch.coworktahoe.v2"
  end
end
