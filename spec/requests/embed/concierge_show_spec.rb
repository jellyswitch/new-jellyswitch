require "rails_helper"

RSpec.describe "Embed::Concierge show", type: :request do
  let(:operator)  { create(:operator, concierge_enabled: true, primary_color: "112233") }
  let!(:location) { create(:location, operator: operator, visible: true) }

  it "asks the visitor to pick a location when unpinned at a multi-location operator" do
    fulton = create(:location, operator: operator, visible: true, name: "Fulton")
    create(:day_pass_type, operator: operator, location: location, name: "Zephyr Day Pass",
                           quantity: 1, amount_in_cents: 2_500)

    get "/embed/concierge/#{operator.subdomain}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Which location are you interested in?")
    expect(response.body).to include(location.name)
    expect(response.body).to include("Fulton")
    expect(response.body).to include("/embed/concierge/#{operator.subdomain}/locations/#{fulton.id}")
    expect(response.body).not_to include("Zephyr Day Pass") # no catalog until a location is picked
  end

  it "skips the location step when pinned via the URL" do
    create(:location, operator: operator, visible: true)
    create(:day_pass_type, operator: operator, location: location, name: "Zephyr Day Pass",
                           quantity: 1, amount_in_cents: 2_500)

    get "/embed/concierge/#{operator.subdomain}/locations/#{location.id}"

    expect(response.body).not_to include("Which location are you interested in?")
    expect(response.body).to include("Zephyr Day Pass")
  end

  it "carries the admin preview token through the location chooser links" do
    create(:location, operator: operator, visible: true)
    operator.update!(concierge_enabled: false)
    token = Embed::ConciergeController.verifier.generate(
      { "operator_id" => operator.id, "exp" => 1.hour.from_now.to_i },
    )

    get "/embed/concierge/#{operator.subdomain}", params: { preview_token: token }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("preview_token=")
  end

  it "renders the location's own offer when pinned to a location" do
    operator.update!(concierge_offer_text: "Brand-wide offer")
    fulton = create(:location, operator: operator, visible: true,
                    concierge_offer_text: "Fulton: day pass refunded if you upgrade")

    get "/embed/concierge/#{operator.subdomain}/locations/#{fulton.id}"

    expect(response.body).to include("Fulton: day pass refunded if you upgrade")
    expect(response.body).not_to include("Brand-wide offer")
  end

  it "renders the widget with the real catalog and inherited theming when active" do
    create(:day_pass_type, operator: operator, location: location, name: "Coworking Day Pass",
                           quantity: 1, amount_in_cents: 2_500)

    get "/embed/concierge/#{operator.subdomain}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What brings you in today")
    expect(response.body).to include("Coworking Day Pass") # catalog-driven option
    expect(response.body).to include("My team needs to meet") # admin-handled option
    expect(response.body).to include("--cx-primary: 112233")  # inherited brand color
    # Shared embed-theme block in the layout (also themes the tour widget).
    expect(response.body).to include("body.embed-tour-request form button")
    # Live-chat wiring (Phase 2): conversations endpoint + the talk-to-team entry.
    expect(response.body).to include("data-checkout-url") # day-pass self-serve checkout
    expect(response.headers["X-Frame-Options"]).to eq("ALLOWALL")
  end

  it "404s when not active and there's no preview token" do
    operator.update!(concierge_enabled: false)
    get "/embed/concierge/#{operator.subdomain}"
    expect(response).to have_http_status(:not_found)
  end

  it "renders the disabled widget for a valid admin preview token" do
    operator.update!(concierge_enabled: false)
    token = Embed::ConciergeController.verifier.generate(
      { "operator_id" => operator.id, "exp" => 1.hour.from_now.to_i }
    )
    get "/embed/concierge/#{operator.subdomain}", params: { preview_token: token }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("not live yet")
  end

  describe "Turnstile" do
    around do |example|
      old = ENV["TURNSTILE_SITEKEY"]
      example.run
    ensure
      ENV["TURNSTILE_SITEKEY"] = old
    end

    it "renders the challenge script and sitekey when configured (the capture endpoint verifies the token)" do
      ENV["TURNSTILE_SITEKEY"] = "sitekey-123"
      get "/embed/concierge/#{operator.subdomain}"
      expect(response.body).to include('data-turnstile-sitekey="sitekey-123"')
      expect(response.body).to include("challenges.cloudflare.com/turnstile")
    end

    it "omits the challenge script when not configured" do
      ENV["TURNSTILE_SITEKEY"] = nil
      get "/embed/concierge/#{operator.subdomain}"
      expect(response.body).to include('data-turnstile-sitekey=""')
      expect(response.body).not_to include("challenges.cloudflare.com")
    end
  end
end
