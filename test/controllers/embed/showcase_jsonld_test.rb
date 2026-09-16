require "test_helper"

# The Showcase's JSON-LD Product markup must carry `image` (required by Google
# for any Product rich result) and a brand; without them Search Console lists
# every tier as invalid under Merchant listings (untethered.space, 2026-09-16).
class Embed::ShowcaseJsonldTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(showcase_enabled: true)
    @location = @operator.locations.first
    @location.update!(visible: true)
    Rails.cache.clear
  end

  test "widget passes the brand name and an absolute image URL from the operator logo" do
    @operator.logo_image.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")),
                                filename: "logo.png", content_type: "image/png")
    get embed_showcase_path(operator_subdomain: @operator.subdomain, location_id: @location.id, format: :js)
    assert_response :success
    assert_match %r{"image":"http://www\.example\.com/rails/active_storage/blobs/}, response.body
    assert_includes response.body, %("brand":"#{@operator.name}")
    assert_includes response.body, %("brand": { "@type": "Brand", "name": DATA.brand })
    assert_includes response.body, "if (DATA.image) product.image = DATA.image;"
  end

  test "location photo wins over the operator logo" do
    @operator.logo_image.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")),
                                filename: "logo.png", content_type: "image/png")
    @location.photo.attach(io: File.open(Rails.root.join("test/fixtures/files/app_icon.png")),
                           filename: "space.png", content_type: "image/png")
    get embed_showcase_path(operator_subdomain: @operator.subdomain, location_id: @location.id, format: :js)
    assert_response :success
    assert_includes response.body, %("image":"#{rails_blob_url(@location.photo, host: "www.example.com")}")
  end

  test "image is null when nothing is attached" do
    get embed_showcase_path(operator_subdomain: @operator.subdomain, location_id: @location.id, format: :js)
    assert_response :success
    assert_includes response.body, %("image":null)
  end
end
