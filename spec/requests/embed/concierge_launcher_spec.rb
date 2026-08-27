require "rails_helper"

RSpec.describe "Embed::Concierge launcher", type: :request do
  let(:operator)  { create(:operator, concierge_enabled: true, embed_accent_override: "#ff5500") }
  let!(:location) { create(:location, operator: operator, visible: true) }

  it "serves the floating launcher JS with the widget URL and brand accent" do
    get "/embed/concierge/#{operator.subdomain}/launcher.js"

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with("text/javascript")
    expect(response.body).to include("jswcx-btn")                          # bubble styles
    expect(response.body).to include("/embed/concierge/#{operator.subdomain}") # widget URL
    expect(response.body).to include("#ff5500")                            # accent theming
    expect(response.headers["Cache-Control"]).to include("public")
  end

  it "pins the widget to a location when location_id is given" do
    other = create(:location, operator: operator, visible: true)

    get "/embed/concierge/#{operator.subdomain}/launcher.js", params: { location_id: other.id }

    expect(response.body).to include("location_id=#{other.id}")
  end

  it "uses the location's own offer in the teaser when location_id is given" do
    operator.update!(concierge_offer_text: "Brand-wide offer")
    fulton = create(:location, operator: operator, visible: true,
                    concierge_offer_text: "Fulton: first day pass on us")

    get "/embed/concierge/#{operator.subdomain}/launcher.js", params: { location_id: fulton.id }

    expect(response.body).to include("Fulton: first day pass on us")
    expect(response.body).not_to include("Brand-wide offer")
  end

  it "falls back to the operator offer when the location has no override" do
    operator.update!(concierge_offer_text: "Brand-wide offer")

    get "/embed/concierge/#{operator.subdomain}/launcher.js", params: { location_id: location.id }

    expect(response.body).to include("Brand-wide offer")
  end

  it "serves a no-op instead of a 404 when the Concierge is disabled" do
    operator.update!(concierge_enabled: false)

    get "/embed/concierge/#{operator.subdomain}/launcher.js"

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with("text/javascript")
    expect(response.body).to include("not enabled")
    expect(response.body).not_to include("jswcx-btn")
  end
end
