require "test_helper"

# Embedded images in automated emails shipped as https://example.org/rails/…
# — ActionText renders rich text outside a request on the renderer's
# placeholder host, and the old rewrite only matched relative paths so it
# never fired. The rewrite must land every ActiveStorage URL shape on
# ASSET_HOST while leaving everything else alone.
class ReplaceBlobUrlsTest < ActiveSupport::TestCase
  HOST = "https://app.jellyswitch.com".freeze

  REDIRECT_PATH = "/rails/active_storage/representations/redirect/signed-blob--sig/signed-var--sig/Cowork%20Tahoe%20Map.png".freeze

  def rewrite(html, host: HOST)
    UserMailer.new.send(:replace_blob_urls, html, host: host)
  end

  test "rehosts the placeholder-host URL ActionText actually emits" do
    html = %(<img src="https://example.org#{REDIRECT_PATH}">)

    assert_equal %(<img src="#{HOST}#{REDIRECT_PATH}">), rewrite(html)
  end

  test "rehosts relative paths from older-rendered bodies" do
    html = %(<img src="#{REDIRECT_PATH}">)

    assert_equal %(<img src="#{HOST}#{REDIRECT_PATH}">), rewrite(html)
  end

  test "covers blobs and proxy variants, and href links to attachments" do
    blob_path = "/rails/active_storage/blobs/proxy/signed--sig/floorplan.pdf"
    html = %(<a href="http://example.org#{blob_path}">floor plan</a>)

    assert_equal %(<a href="#{HOST}#{blob_path}">floor plan</a>), rewrite(html)
  end

  test "leaves already-correct hosts pointed at the app host (idempotent)" do
    html = %(<img src="#{HOST}#{REDIRECT_PATH}">)

    assert_equal html, rewrite(html)
  end

  test "does not touch non-ActiveStorage URLs" do
    html = %(<a href="https://example.org/pricing"><img src="https://cdn.example.com/logo.png"></a>)

    assert_equal html, rewrite(html)
  end

  test "a trailing slash on the host does not double up" do
    html = %(<img src="https://example.org#{REDIRECT_PATH}">)

    assert_equal %(<img src="#{HOST}#{REDIRECT_PATH}">), rewrite(html, host: "#{HOST}/")
  end

  test "no host configured leaves the body untouched rather than mangling it" do
    html = %(<img src="https://example.org#{REDIRECT_PATH}">)

    assert_equal html, rewrite(html, host: nil)
  end
end
